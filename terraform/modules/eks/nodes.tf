# ---------------------------------------------------------------------------
# Managed node group in private subnets with a hardened launch template:
# IMDSv2 required (hop limit 1 so pods can't steal node creds), encrypted EBS.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.${local.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEKS_CNI_Policy",
    "AmazonEC2ContainerRegistryReadOnly",
    "AmazonSSMManagedInstanceCore", # SSM Session Manager instead of SSH keys
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "node" {
  name_prefix = "${var.cluster_name}-node-"
  description = "Hardened launch template for ${var.cluster_name} managed nodes"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.eks.arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }

  tags = var.tags
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  ami_type        = var.node_ami_type
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    workload = "general"
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Core add-ons managed by EKS so they get patched with the control plane (SI-2).
resource "aws_eks_addon" "this" {
  for_each                    = toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"])
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.default]
}
