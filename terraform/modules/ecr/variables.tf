variable "repository_names" {
  description = "ECR repositories to create."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key for image encryption. A key is created if null."
  type        = string
  default     = null
}

variable "untagged_expiry_days" {
  description = "Expire untagged images after N days."
  type        = number
  default     = 14
}

variable "max_tagged_images" {
  description = "Keep at most N tagged images per repository."
  type        = number
  default     = 100
}

variable "pull_principal_arns" {
  description = "Extra IAM principals allowed to pull (e.g. a higher-side promotion account)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
