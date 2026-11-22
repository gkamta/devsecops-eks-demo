# ---------------------------------------------------------------------------
# Keyless CI auth: GitHub Actions exchanges its OIDC token for short-lived AWS
# credentials. No long-lived access keys stored as secrets (IA-5, AC-2).
# ---------------------------------------------------------------------------
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
  tags            = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in var.allowed_subjects : "repo:${var.github_repository}:${s}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  tags                 = var.tags
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      sid = "EcrPush"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeImages",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = var.ecr_repository_arns
    }
  }

  statement {
    sid       = "EksDescribe"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${data.aws_partition.current.partition}:eks:*:${data.aws_caller_identity.current.account_id}:cluster/*"]
  }

  dynamic "statement" {
    for_each = var.state_bucket_arn == null ? [] : [1]
    content {
      sid       = "TfState"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      resources = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
    }
  }

  dynamic "statement" {
    for_each = var.lock_table_arn == null ? [] : [1]
    content {
      sid       = "TfLock"
      actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
      resources = [var.lock_table_arn]
    }
  }
}

resource "aws_iam_role_policy" "ci" {
  name   = "ci-least-privilege"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}

# Read-only for terraform plan.
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}
