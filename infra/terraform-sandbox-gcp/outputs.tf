output "project_id" {
  value = var.project_id
}

output "cluster_name" {
  value = google_container_cluster.this.name
}

output "zone" {
  value = var.zone
}

output "artifact_registry_repo" {
  description = "Empty when enable_artifact_registry is false."
  value       = try("${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.agent[0].repository_id}", "")
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${var.zone} --project ${var.project_id}"
}
