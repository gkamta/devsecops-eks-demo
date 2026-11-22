variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes control-plane version."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC to deploy into."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control-plane ENIs and node group."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API publicly. Keep false for IL4/IL5; use a bastion, VPN, or SSM."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "Allowed CIDRs when endpoint_public_access = true. Never 0.0.0.0/0."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "public_access_cidrs must not contain 0.0.0.0/0."
  }
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_ami_type" {
  description = "Managed node group AMI type (AL2023 by default; use a custom STIG'd AMI via launch template in production)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_desired_size" {
  description = "Desired node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count."
  type        = number
  default     = 4
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size for nodes (encrypted)."
  type        = number
  default     = 50
}

variable "log_retention_days" {
  description = "Control-plane log retention."
  type        = number
  default     = 365
}

variable "app_namespace" {
  description = "Kubernetes namespace of the workload that gets an IRSA role."
  type        = string
  default     = "mission-api"
}

variable "app_service_account" {
  description = "Kubernetes service account name bound to the IRSA role."
  type        = string
  default     = "mission-api"
}

variable "app_policy_json" {
  description = "Optional IAM policy JSON granted to the workload through IRSA (least privilege). Null = no permissions."
  type        = string
  default     = null
}

variable "cluster_admin_principal_arns" {
  description = "IAM principals (e.g. the CI deploy role, an SSO admin role) granted cluster admin via EKS access entries."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
