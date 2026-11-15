# GKE Standard (the playground does not allow Autopilot).
# The node settings are on the cluster itself, with no separate pool, so GKE never creates
# a default 100 GB balanced disk that the sandbox policy would reject.
resource "google_container_cluster" "this" {
  name     = "${var.name_prefix}-sandbox"
  project  = var.project_id
  location = var.zone

  initial_node_count  = var.node_count
  deletion_protection = false

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_artifact_registry_repository" "agent" {
  count         = var.enable_artifact_registry ? 1 : 0
  project       = var.project_id
  location      = var.region
  repository_id = "tiny-agent"
  format        = "DOCKER"
}
