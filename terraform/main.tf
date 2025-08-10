terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

############################
# Variables (inlined)
############################

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "cloudbuild_ssh_key_pub" {
  description = "The public SSH key for the Cloud Build service account."
  type        = string
}

variable "cloudbuild_ssh_key_secret_id" {
  description = "Secret Manager secret ID for the Cloud Build private key."
  type        = string
}

variable "region" {
  description = "GCP region (choose free tier eligible, e.g., us-west1/us-central1/us-east1)"
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone (e.g., us-west1-b)"
  type        = string
  default     = "us-west1-b"
}

variable "resource_prefix" {
  description = "Prefix for resource names (e.g., production-)"
  type        = string
  default     = "production-"
}


variable "machine_type" {
  description = "Compute Engine machine type (e2-micro recommended for free tier)"
  type        = string
  default     = "e2-micro"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB (30GB recommended)"
  type        = number
  default     = 30
}

variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork name (optional)"
  type        = string
  default     = null
}

variable "repo_url" {
  description = "Git repository URL to deploy (this repo)"
  type        = string
}

variable "secret_name" {
  description = "Base Secret Manager name storing .env (dotenv format, without prefix)"
  type        = string
  default     = "env"
}

variable "dotenv_content" {
  description = "Initial .env content to create as Secret Manager version (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub organization/user that hosts the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "tag_regex" {
  description = "Tag regex to trigger Cloud Build (e.g., ^v.*)"
  type        = string
  default     = "^v.*"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_compute_image" "ubuntu_lts" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

locals {
  # Base name for all resources, sanitized and concise (e.g., "prod-n8n")
  base_raw = "${var.resource_prefix}n8n"
  base     = trim(replace(lower(local.base_raw), "/[^a-z0-9-]/", "-"), "-")

  # Canonical resource names
  vm_name = local.base                   # e.g., prod-n8n
  ip_name = "${local.base}-ip"           # e.g., prod-n8n-ip
  fw_web_name = "${local.base}-fw-web"    # e.g., prod-n8n-fw-web
  fw_ssh_name = "${local.base}-fw-ssh"    # e.g., prod-n8n-fw-ssh
  tag     = local.base                   # network tag

  # Service account IDs (max 30 chars, must be simple)
  sa_vm_id = trim(substr("${local.base}-vm-sa", 0, 30), "-")   # e.g., prod-n8n-vm-sa
  sa_cb_id = trim(substr("${local.base}-cb-sa", 0, 30), "-")   # e.g., prod-n8n-cb-sa

  # Secret name (prefixed), kept simple
  secret_name_full = trim(replace(lower("${local.base}-${var.secret_name}"), "/[^a-z0-9-_]/", "-"), "-")

}

data "google_project" "current" {}

resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com"
  ])
  service                    = each.value
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_compute_address" "static_ip" {
  name   = local.ip_name
  region = var.region
}

resource "google_compute_firewall" "allow_http_https" {
  name    = local.fw_web_name
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # Allow from anywhere by default; tighten as needed
  source_ranges = ["0.0.0.0/0"]

  # Use standard tags so Console shows HTTP/HTTPS toggles as ON
  target_tags = ["http-server", "https-server"]
}

# SSH over IAP only (Google IAP TCP forwarding range)
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = local.fw_ssh_name
  network = var.network

  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]

  target_tags = [local.tag]
}

resource "google_service_account" "vm_sa" {
  account_id   = local.sa_vm_id
  display_name = "n8n VM service account"
}

resource "google_project_iam_member" "vm_sa_secret_accessor" {
  project = var.project_id
  role   = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${google_service_account.vm_sa.email}"
}

# Custom service account for Cloud Build runtime (used by trigger)
resource "google_service_account" "cloudbuild_sa" {
  account_id   = local.sa_cb_id
  display_name = "Cloud Build runtime for ${local.base}"
}

# Allow Cloud Build service agent to impersonate the custom SA
resource "google_service_account_iam_member" "cloudbuild_impersonate" {
  service_account_id = google_service_account.cloudbuild_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

# Allow the Cloud Build service agent to use the runtime service account (ActAs)
resource "google_service_account_iam_member" "cloudbuild_impersonate_user" {
  service_account_id = google_service_account.cloudbuild_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_sa_secret_accessor" {
  project = var.project_id
  role   = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Allow Cloud Build runtime SA to use IAP TCP tunneling for SSH
resource "google_project_iam_member" "cloudbuild_sa_iap_tunnel" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Allow the runtime SA to run Cloud Build jobs
resource "google_project_iam_member" "cloudbuild_sa_builds_editor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Allow the runtime SA to write logs to Cloud Logging
resource "google_project_iam_member" "cloudbuild_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Optional but recommended: viewer for compute instance metadata
resource "google_project_iam_member" "cloudbuild_sa_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_secret_manager_secret" "dotenv" {
  project   = var.project_id
  secret_id = local.secret_name_full
  replication {
    auto {}
  }
  depends_on = [
    google_project_service.services
  ]
}

resource "google_secret_manager_secret_version" "dotenv" {
  count       = length(var.dotenv_content) > 0 ? 1 : 0
  secret      = google_secret_manager_secret.dotenv.id
  secret_data = var.dotenv_content
  depends_on  = [google_secret_manager_secret.dotenv]
}

resource "google_secret_manager_secret" "cloudbuild_ssh_key" {
  project     = var.project_id
  secret_id   = var.cloudbuild_ssh_key_secret_id
  replication {
    auto {}
  }
  # Ensure the Secret Manager API is enabled before creating the secret
  depends_on = [
    google_project_service.services
  ]
}

resource "google_secret_manager_secret_version" "cloudbuild_ssh_key_version" {
  secret      = google_secret_manager_secret.cloudbuild_ssh_key.id
  secret_data = file("cloudbuild-ssh-key")
  depends_on  = [
    google_secret_manager_secret.cloudbuild_ssh_key
  ]
}

locals {
  startup_script = <<-EOT
    #!/usr/bin/env bash
    # Stop the script immediately if any command fails
    set -euxo pipefail
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Remove any stale/broken Docker repo entry from previous runs
    rm -f /etc/apt/sources.list.d/docker.list || true

    # Update package list and install prerequisites for Docker
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https git

    # Download the Docker repository signing key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Configure the Docker repository (avoid Terraform interpolation conflicts)
    . /etc/os-release || true
    codename="$UBUNTU_CODENAME"
    if [ -z "$codename" ]; then codename="$VERSION_CODENAME"; fi
    if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
      codename="$(lsb_release -cs)"
    fi
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' "$(dpkg --print-architecture)" "$codename" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package list and install Docker Engine and plugins
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Ensure Docker daemon is running and active
    systemctl enable docker
    systemctl start docker
    
    # Wait for Docker to be fully ready before proceeding
    until docker info > /dev/null 2>&1; do
      echo "Waiting for Docker daemon to be ready..."
      sleep 2
    done

    # Add cloudbuild-sa user to the 'docker' group to run docker commands without sudo
    if id -u cloudbuild-sa >/dev/null 2>&1; then
      usermod -aG docker cloudbuild-sa
    fi

    # Install Google Cloud SDK (needed for gcloud commands on the VM)
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "Installing Google Cloud SDK repo…"
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/google-cloud.gpg
      chmod a+r /etc/apt/keyrings/google-cloud.gpg
      echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
      apt-get update -y
      apt-get install -y google-cloud-sdk
    fi
    
    # Git clone the repository and prepare the application directory
    APP_DIR=/opt/n8n
    if [ ! -d "$APP_DIR/.git" ]; then
      rm -rf "$APP_DIR" || true
      mkdir -p "$APP_DIR"
      git clone ${var.repo_url} "$APP_DIR"
    else
      git -C "$APP_DIR" pull --rebase || true
    fi

    echo "Startup script finished."
  EOT
}

locals {
  ssh_public_key = file(var.cloudbuild_ssh_key_pub)
}

resource "google_compute_instance" "vm" {
  name         = local.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  # Keep custom tag for IAP-SSH rule, and add standard http/https tags for Console display
  tags = [local.tag, "http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu_lts.self_link
      type  = "pd-standard"
      size  = var.boot_disk_size_gb
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  service_account {
    email  = google_service_account.vm_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    enable-oslogin = "FALSE"
    startup-script = local.startup_script
    ssh-keys       = "cloudbuild-sa:${local.ssh_public_key} cloudbuild-sa"
  }

  # Hostname not set; GCE default applies

  depends_on = [
    google_project_service.services,
    google_compute_firewall.allow_http_https,
    google_compute_firewall.allow_ssh_iap
  ]
}

output "vm_ip" {
  description = "Static external IP address"
  value       = google_compute_address.static_ip.address
}

output "instance_name" {
  description = "VM name"
  value       = google_compute_instance.vm.name
}

output "secret_name" {
  description = "Secret Manager secret name for .env"
  value       = google_secret_manager_secret.dotenv.secret_id
}

# Cloud Build trigger (GitHub tag push)
resource "google_cloudbuild_trigger" "tag_trigger" {
  name = "n8n-deploy-on-tag"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      tag = var.tag_regex
    }
  }

  filename = "cicd/cloudbuild.yaml"

  # Run builds as the custom runtime SA (full resource name required)
  service_account = "projects/${var.project_id}/serviceAccounts/${google_service_account.cloudbuild_sa.email}"

  substitutions = {
    _INSTANCE_NAME = local.vm_name
    _ZONE          = var.zone
    _SECRET_NAME   = local.secret_name_full
    _REPO_URL      = var.repo_url
    _SSH_KEY_SECRET_NAME = var.cloudbuild_ssh_key_secret_id
  }

  depends_on = [
    google_project_service.services,
    google_compute_instance.vm
  ]
}

output "cloudbuild_trigger_id" {
  description = "Cloud Build trigger ID"
  value       = google_cloudbuild_trigger.tag_trigger.id
}
