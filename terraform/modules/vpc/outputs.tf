output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes and control-plane ENIs)."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT / internet-facing LBs only)."
  value       = aws_subnet.public[*].id
}

output "private_route_table_ids" {
  description = "Private route table IDs (for gateway VPC endpoints)."
  value       = aws_route_table.private[*].id
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
