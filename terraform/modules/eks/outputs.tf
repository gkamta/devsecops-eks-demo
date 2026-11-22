output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "app_irsa_role_arn" {
  description = "IAM role ARN to annotate on the workload ServiceAccount (eks.amazonaws.com/role-arn)."
  value       = aws_iam_role.app_irsa.arn
}

output "kms_key_arn" {
  description = "KMS key used for secrets envelope encryption."
  value       = aws_kms_key.eks.arn
}
