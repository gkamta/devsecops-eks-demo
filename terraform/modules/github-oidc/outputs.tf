output "role_arn" {
  description = "Role ARN to set as the AWS_CI_ROLE_ARN GitHub variable."
  value       = aws_iam_role.ci.arn
}
