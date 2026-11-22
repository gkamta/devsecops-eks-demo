output "partition" {
  description = "AWS partition in use (aws-us-gov for GovCloud)."
  value       = data.aws_partition.current.partition
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  description = "ECR repository URLs."
  value       = module.ecr.repository_urls
}

output "app_irsa_role_arn" {
  description = "Annotate the mission-api ServiceAccount with this role."
  value       = module.eks.app_irsa_role_arn
}

output "github_actions_role_arn" {
  description = "Set as the AWS_CI_ROLE_ARN repository variable in GitHub."
  value       = module.github_oidc.role_arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
