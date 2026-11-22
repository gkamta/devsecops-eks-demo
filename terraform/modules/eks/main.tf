data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  dns_suffix = data.aws_partition.current.dns_suffix
}

# ---------------------------------------------------------------------------
# KMS: envelope encryption of Kubernetes Secrets in etcd (SC-28) + logs.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  # checkov:skip=CKV_AWS_109:Key policy root statement is the AWS-recommended default.
  # checkov:skip=CKV_AWS_111:Key policy root statement is the AWS-recommended default.
  # checkov:skip=CKV_AWS_356:Key policies must use "*" as the resource.
  statement {
    sid       = "EnableRootAccountPermissions"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.${local.dns_suffix}"]
    }
  }
}

data "aws_region" "current" {}

resource "aws_kms_key" "eks" {
  description             = "${var.cluster_name} EKS secrets and log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = var.tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "cluster" {
  # EKS writes to this exact name; creating it first lets us set retention + KMS.
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.eks.arn
  tags              = var.tags
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "Additional EKS control-plane security group"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_name}-cluster" })
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# Access entries replace the legacy aws-auth ConfigMap (AC-2 account management).
resource "aws_eks_access_entry" "admins" {
  for_each      = toset(var.cluster_admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admins" {
  for_each      = toset(var.cluster_admin_principal_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admins]
}

# ---------------------------------------------------------------------------
# IRSA: IAM OIDC provider so pods assume IAM roles via their service account
# (no node-level credentials shared across workloads, AC-6 least privilege).
# ---------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.${local.dns_suffix}"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

locals {
  oidc_issuer_host = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

data "aws_iam_policy_document" "app_irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${var.app_namespace}:${var.app_service_account}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.${local.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "app_irsa" {
  name               = "${var.cluster_name}-${var.app_service_account}-irsa"
  assume_role_policy = data.aws_iam_policy_document.app_irsa_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "app_irsa" {
  count  = var.app_policy_json == null ? 0 : 1
  name   = "workload"
  role   = aws_iam_role.app_irsa.id
  policy = var.app_policy_json
}
