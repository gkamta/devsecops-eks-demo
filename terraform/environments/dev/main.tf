data "aws_partition" "current" {}

locals {
  name = "${var.project}-${var.environment}"
  azs  = var.azs

  tags = merge({
    Project        = var.project
    Environment    = var.environment
    Owner          = var.owner
    ManagedBy      = "terraform"
    Classification = var.classification
    Repository     = var.github_repository
  }, var.extra_tags)
}

# Guardrail: fail the plan if credentials point at the wrong partition
# (e.g. commercial creds used against a GovCloud stack).
check "partition_guardrail" {
  assert {
    condition     = data.aws_partition.current.partition == var.expected_partition
    error_message = "Credentials resolve to partition ${data.aws_partition.current.partition}, expected ${var.expected_partition}."
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  cluster_name         = local.name
  cidr_block           = var.vpc_cidr
  azs                  = local.azs
  private_subnet_cidrs = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnet_cidrs  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, 200 + i)]
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names = [var.project]
  tags             = local.tags
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  role_name            = "${local.name}-github-actions"
  github_repository    = var.github_repository
  create_oidc_provider = var.create_github_oidc_provider
  ecr_repository_arns  = values(module.ecr.repository_arns)
  tags                 = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.name
  kubernetes_version     = var.kubernetes_version
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs

  app_namespace       = var.project
  app_service_account = var.project

  cluster_admin_principal_arns = concat([module.github_oidc.role_arn], var.admin_principal_arns)

  tags = local.tags
}
