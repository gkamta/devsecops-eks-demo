variable "aws_region" {
  description = "AWS region. GovCloud: us-gov-west-1 or us-gov-east-1."
  type        = string
  default     = "us-gov-west-1"
}

variable "expected_partition" {
  description = "Guardrail: the partition this stack must deploy into (aws-us-gov for GovCloud, aws for commercial demo)."
  type        = string
  default     = "aws-us-gov"

  validation {
    condition     = contains(["aws", "aws-us-gov"], var.expected_partition)
    error_message = "expected_partition must be aws or aws-us-gov."
  }
}

variable "allowed_account_ids" {
  description = "Guardrail: refuse to run against any other AWS account."
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Environment name (dev/stage/prod)."
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "mission-api"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.40.0.0/16"
}

variable "azs" {
  description = "Explicit AZ allowlist (deterministic; avoids silent expansion when AWS adds a zone)."
  type        = list(string)
  default     = ["us-gov-west-1a", "us-gov-west-1b", "us-gov-west-1c"]

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Use 2-3 AZs for HA."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT (dev) vs one per AZ (prod)."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "endpoint_public_access" {
  description = "Expose the EKS API publicly (dev convenience only)."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach a public EKS API endpoint."
  type        = list(string)
  default     = []
}

variable "github_repository" {
  description = "owner/repo whose Actions workflows may assume the CI role."
  type        = string
  default     = "OWNER/devsecops-eks-demo"
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider (set false if it already exists in the account)."
  type        = bool
  default     = true
}

variable "admin_principal_arns" {
  description = "Additional IAM principals (e.g. SSO admin role) granted EKS cluster admin."
  type        = list(string)
  default     = []
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "george.kamta"
}

variable "classification" {
  description = "Data classification tag (e.g. CUI, IL4, IL5)."
  type        = string
  default     = "CUI"
}

variable "extra_tags" {
  description = "Extra tags merged into the defaults."
  type        = map(string)
  default     = {}
}
