output "region" {
  value = var.region
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "ecr_repository_url" {
  description = "Empty when enable_ecr is false."
  value       = try(aws_ecr_repository.agent[0].repository_url, "")
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
