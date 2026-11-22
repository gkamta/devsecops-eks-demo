variable "name" {
  description = "Name prefix for all VPC resources."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.40.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across (2-3 recommended)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private (workload) subnets, one per AZ."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (NAT gateways / load balancers only), one per AZ."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway (cheaper, dev) instead of one per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name, used for Kubernetes subnet discovery tags."
  type        = string
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs (AU-11). 365+ recommended for DoD."
  type        = number
  default     = 365
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for encrypting flow logs. A key is created if null."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

variable "enable_vpc_endpoints" {
  description = "Create S3 gateway + interface endpoints (ECR, STS, logs, EC2, EKS) so nodes can run without internet egress (IL5 / air-gap pattern)."
  type        = bool
  default     = true
}

variable "interface_endpoint_services" {
  description = "Interface endpoint service short names."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "logs", "ec2", "eks", "kms", "elasticloadbalancing"]
}
