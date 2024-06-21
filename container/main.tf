terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.51.0"
    }
  }
}

variable "GOOGLE_CLOUD_PROJECT_ID" {
  type = string
}

provider "google" {
  project = var.GOOGLE_CLOUD_PROJECT_ID
  
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
    annotations = { "run.googleapis.com/ingress" = "all" }
  }

  template { // Describes the data our CloudRun revision should have when created
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello"

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
  location    = google_cloud_run_service.middleware_cloudrun_instance.location
  project     = google_cloud_run_service.middleware_cloudrun_instance.project
  service     = google_cloud_run_service.middleware_cloudrun_instance.name

  policy_data = data.google_iam_policy.noauth.policy_data
}