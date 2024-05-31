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

resource "google_compute_instance" "default" {
  name         = "my-instance"
  machine_type = "n2-standard-2"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  // Local SSD disk
  scratch_disk {
    interface = "NVME"
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
   // ssh-keys = "jon:${file(pathexpand("~/.ssh/id_rsa.pub"))}"
  }
}
