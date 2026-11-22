data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecr_kms" {
  # checkov:skip=CKV_AWS_109:Key policy root statement is the AWS-recommended default.
  # checkov:skip=CKV_AWS_111:Key policy root statement is the AWS-recommended default.
  # checkov:skip=CKV_AWS_356:Key policies must use "*" as the resource.
  statement {
    sid       = "EnableRootAccountPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "ecr" {
  count                   = var.kms_key_arn == null ? 1 : 0
  description             = "ECR image encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.ecr_kms.json
  tags                    = var.tags
}

locals {
  kms_key_arn = coalesce(var.kms_key_arn, try(aws_kms_key.ecr[0].arn, null))
}

# Immutable tags: a tag can never be re-pointed at different bits, so the
# digest that passed scanning/signing is the one that gets deployed (CM-2, SI-7).
resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repository_names)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.kms_key_arn
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Cap tagged image count"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_tagged_images
        }
        action = { type = "expire" }
      },
    ]
  })
}

data "aws_iam_policy_document" "pull" {
  count = length(var.pull_principal_arns) > 0 ? 1 : 0
  statement {
    sid = "CrossAccountPull"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    principals {
      type        = "AWS"
      identifiers = var.pull_principal_arns
    }
  }
}

resource "aws_ecr_repository_policy" "pull" {
  for_each   = length(var.pull_principal_arns) > 0 ? aws_ecr_repository.this : {}
  repository = each.value.name
  policy     = data.aws_iam_policy_document.pull[0].json
}

# Registry-level enhanced scanning (Amazon Inspector) for continuous re-scan
# as new CVEs are published (RA-5).
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}
