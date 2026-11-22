terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # GovCloud partition is inferred from the region (aws-us-gov); validated below.
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = local.tags
  }
}
