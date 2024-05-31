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

variable "GOOGLE_CLOUD_ZONE" {
  type    = string
  default = "us-central1-a"
}

provider "google" {
  project = var.GOOGLE_CLOUD_PROJECT_ID
}

locals {
  cloud_init = templatefile("./cloudinit.template.yml", {
    NAME                  = "my-nginx-1"
    NGINX_CONTAINER_IMAGE = "nginx:1.27.0-bookworm"
  })
}

resource "google_compute_instance" "default" {
  name         = "my-instance"
  machine_type = "n2-standard-2"
  zone         = var.GOOGLE_CLOUD_ZONE
  tags         = ["my-allow-80"] // To adopt specific firewall rules

  // Enables Terraform to stop the Compute Engine instance in order to update the .yml config.
  // See: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance#allow_stopping_for_update
  allow_stopping_for_update = true

  // Chooses the prefab OS that will run on the Compute Engine instance and host our services.
  // See: https://cloud.google.com/container-optimized-os/docs/how-to/create-configure-instance#list-images
  boot_disk {
    initialize_params { image = "projects/cos-cloud/global/images/cos-101-17162-40-5" }
  }

  // Mounts the SSD disk (provisioned in this file) on the current instance with read/write permissions.
  attached_disk {
    mode        = "READ_WRITE"
    device_name = "my-ssd"
    source      = google_compute_disk.ssd_persistent_disk.self_link
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys  = "jon:${file(pathexpand("~/.ssh/id_rsa.pub"))}"
    user-data = local.cloud_init
  }

  // Since the 'compute-engine.yml' isn't part of observed state by Terraform is not possible to trigger a new 
  // provisioning pipeline when 'only' said file is changed. With this workaround we add a new additional trigger
  // (the sha256 of the 'compute-engine.yml' file) that allows us to keep in sync the local and GCP configs. 
  // See:
  // - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1703#issuecomment-1201846108
  // - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1703#issuecomment-1200720557
  lifecycle { replace_triggered_by = [null_resource.cloud_init_trigger.id] }
}

// Resource: A 'dummy' resource that doesn't create anything but acts as trigger for the update of a Compute.
//
// Description:
// Since Terraform doesn't react to cloud-init.yml file changes because it is transparent to the field observed
// by it we have found this simple workaround. When the cloud-init.yml file changes (either by a change in its 
// template content or its interpolation params) the sha256 of said file changes as well ans this. in turn,
// triggers an upgrade of the Compute Engine instance below. For further information, see: 
// - https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource
// - https://developer.hashicorp.com/terraform/cloud-docs/run/run-environment?optInFrom=terraform-io#environment-variables
resource "null_resource" "cloud_init_trigger" {
  triggers = { cloud_init_yml_sha256 = sha256(local.cloud_init) }
}

// Resource: Provision a Persistent SSD Disk storage for the Compute Engine instance.
//
// Description:
// A mounted file system used by a Docker volume
// we want be able to have a persistent space across upgrades (eg. VM destroy).
resource "google_compute_disk" "ssd_persistent_disk" {
  provider = google-beta

  zone    = var.GOOGLE_CLOUD_ZONE
  project = var.GOOGLE_CLOUD_PROJECT_ID

  name = "my-ssd"

  size                      = 50       // Fixed size disk to 50GB (auto-resize not available)
  type                      = "pd-ssd" // Uses an SSD as hardware (HDD is also available)
  physical_block_size_bytes = 4096     // Lowest block size available

  // Even when Terraform wants to provision a new resource the old one shouldn't get destroyed
  lifecycle { prevent_destroy = false }
}   

// Resource: Provision Firewall rules for every Compute Engine instance w/ 'my-allow-80' tags
//
// Description:
// By default GCP blocks all inbound traffic to the Compute instance, in order to enable communication we open
// the HTTP port (80) to inbound and outbound traffic. Keep in mind that since the instances
// are provisioned behind a VPC it's still possible to hide them from external access (right now this is not the case).
resource "google_compute_firewall" "my-firewall-rules" {
  provider = google-beta

  project = var.GOOGLE_CLOUD_PROJECT_ID

  name        = "my-firewall-rules"
  description = "GCP Firewall rule for Compute Engine instances with 'my-allow-80' tag"

  network     = "default"       // This rules apply to the project VPC provisioned in ./network.tf
  target_tags = ["my-allow-80"] // All Compute instances with this tags use this firewall rule 

  
  source_ranges = ["0.0.0.0/0"] // Allows traffic from all (VPC internal only) sources 
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}
