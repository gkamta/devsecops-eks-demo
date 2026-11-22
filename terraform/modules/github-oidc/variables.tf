variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes."
  type        = string
}

variable "github_repository" {
  description = "owner/repo allowed to assume the role."
  type        = string
}

variable "allowed_subjects" {
  description = "OIDC sub patterns (relative to repo:<owner/repo>:) allowed to assume the role."
  type        = list(string)
  default     = ["ref:refs/heads/main", "environment:dev", "environment:stage", "environment:prod", "pull_request"]
}

variable "create_oidc_provider" {
  description = "Create the token.actions.githubusercontent.com IAM OIDC provider (once per account)."
  type        = bool
  default     = true
}

variable "ecr_repository_arns" {
  description = "ECR repositories CI may push to."
  type        = list(string)
  default     = []
}

variable "state_bucket_arn" {
  description = "Terraform state bucket ARN (for plan)."
  type        = string
  default     = null
}

variable "lock_table_arn" {
  description = "Terraform lock table ARN (for plan)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
