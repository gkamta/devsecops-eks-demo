# ---------------------------------------------------------------------------
# Private VPC endpoints: lets EKS nodes pull images from ECR, get IRSA creds
# from STS and ship logs without traversing the NAT gateway. In an IL5 /
# disconnected enclave the NAT is removed entirely and these become mandatory
# (SC-7 boundary protection).
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = merge(var.tags, { Name = "${var.name}-s3" })
}

resource "aws_security_group" "endpoints" {
  # checkov:skip=CKV2_AWS_5:Attached to the interface VPC endpoints below (for_each not resolved by checkov).
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.name}-vpce"
  description = "HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    description = "Responses within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = var.enable_vpc_endpoints ? toset(var.interface_endpoint_services) : toset([])
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(var.tags, { Name = "${var.name}-${each.value}" })
}
