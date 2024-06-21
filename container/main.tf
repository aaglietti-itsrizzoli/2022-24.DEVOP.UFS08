terraform {
  required_providers {

    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.8.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}




variable "GOOGLE_CLOUD_PROJECT_ID" {
  type = string
}

variable "DOPPLER_TOKEN" {
  type = string
}

provider "google" {
  project = var.GOOGLE_CLOUD_PROJECT_ID

}



provider "doppler" { // Doppler secret manager for PostgreSQL (read/write access)
  doppler_token = var.DOPPLER_TOKEN
  alias         = "my_project"
}


data "doppler_secrets" "my_project" {
  provider = doppler.my_project

}

/*output "pippo" {
  value = nonsensitive(data.doppler_secrets.my_project.map.SECRET1)
}*/




resource "google_sql_database_instance" "masterdb" {
  provider = google

  region  = "us-central1"
  project = var.GOOGLE_CLOUD_PROJECT_ID

  name                = "db1"
  database_version    = "POSTGRES_14"
  deletion_protection = false       // WARNING!!!
  settings {                        // Define Cloud SQL settings
    tier            = "db-g1-small" // Tier of the Machine (# of CPUs, RAM and Disk size)
    disk_autoresize = true          // Auto-resize the Disk space if not enough for current data

  }
}


resource "google_sql_user" "db1user1" {
  provider = google

  instance = google_sql_database_instance.masterdb.name

  // To grant readonly permissions to an user run the following script:
  // https://github.com/hashicorp/terraform-provider-google/issues/10438
  name     = nonsensitive(data.doppler_secrets.my_project.map.MASTER_DB_USER1)
  password = data.doppler_secrets.my_project.map.MASTER_DB_USER1_PSW
}




resource "doppler_secret" "db1_host" {
  provider = doppler.my_project

  // Reserved secrets, see: https://docs.doppler.com/docs/secrets#reserved-secrets
  config  = nonsensitive(data.doppler_secrets.my_project.map.DOPPLER_CONFIG)
  project = nonsensitive(data.doppler_secrets.my_project.map.DOPPLER_PROJECT)

  // Sets the 'name' variable to the output 'value' 
  name       = "MASTER_DB_HOST"
  value      = google_sql_database_instance.masterdb.public_ip_address
  visibility = "unmasked"
}





resource "google_cloud_run_service" "middleware_cloudrun_instance" {
  provider = google

  project  = var.GOOGLE_CLOUD_PROJECT_ID
  location = "us-central1"

  name = "middleware"

  // Defines the configuration for our CloudRun (Service).
  // For reference, see: https://cloud.google.com/run/docs/reference/rpc/google.cloud.run.v1#revisiontemplate
  metadata {
    // See: https://cloud.google.com/sdk/gcloud/reference/run/deploy#--ingress
    annotations = { "run.googleapis.com/ingress" = "all", "run.googleapis.com/operation-id" = "83eb5dc9-b709-43e5-8b53-0758838ad192" }
  }


  template { // Describes the data our CloudRun revision should have when created
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello"
        env {
          name  = "DB1_HOST"
          value = nonsensitive(data.doppler_secrets.my_project.map.MASTER_DB_HOST)

        }

        env {
          name  = "DB1_USER1"
          value = data.doppler_secrets.my_project.map.MASTER_DB_USER1
        }

        env {
          name  = "DB1_USER1_PSW"
          value = data.doppler_secrets.my_project.map.MASTER_DB_USER1_PSW
        }

        // Defines which ports (and protocol) are enabled/exposed on the Docker container
        ports {
          name           = "http1"
          container_port = 8080
        }
      }
    }

    // Defines the configuration for our CloudRun (Revision).
    // For reference, see: https://cloud.google.com/run/docs/reference/rpc/google.cloud.run.v1#revisiontemplate
  }

  traffic { // Once the startup probe is satisfied redirects all traffic to the latest instance
    percent         = 100
    latest_revision = true
  }


}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.middleware_cloudrun_instance.location
  project  = google_cloud_run_service.middleware_cloudrun_instance.project
  service  = google_cloud_run_service.middleware_cloudrun_instance.name

  policy_data = data.google_iam_policy.noauth.policy_data
}