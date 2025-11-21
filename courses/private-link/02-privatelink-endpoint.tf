# This file creates the VPC endpoint for CockroachDB PrivateLink

# Use existing VPC data
data "aws_vpc" "existing" {
  id = var.vpc_id
}

variable "vpc_id" {
  description = "VPC ID from infrastructure"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the endpoint"
  type        = list(string)
}

variable "service_name" {
  description = "CockroachDB PrivateLink service name"
  type        = string
}

variable "cluster_name" {
  description = "CockroachDB cluster name"
  type        = string
  default     = "free-tier-14"
}

# Security group for VPC endpoint
resource "aws_security_group" "cockroachdb_privatelink" {
  name        = "cockroachdb-privatelink-sg-${var.resource_suffix}"
  description = "Security group for CockroachDB PrivateLink endpoint"
  vpc_id      = var.vpc_id

  ingress {
    description = "CockroachDB SQL"
    from_port   = 26257
    to_port     = 26257
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "CockroachDB-PrivateLink-SG"
    Cluster     = var.cluster_name
    Environment = "Lab"
  }
}

# VPC Endpoint for CockroachDB
resource "aws_vpc_endpoint" "cockroachdb" {
  vpc_id              = var.vpc_id
  service_name        = var.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.cockroachdb_privatelink.id]

  # This enables automatic private DNS resolution
  private_dns_enabled = true

  tags = {
    Name        = "CockroachDB-PrivateLink-Endpoint"
    Cluster     = var.cluster_name
    Environment = "Lab"
  }
}

# Outputs
output "vpc_endpoint_id" {
  value = aws_vpc_endpoint.cockroachdb.id
}

output "vpc_endpoint_dns" {
  value = length(aws_vpc_endpoint.cockroachdb.dns_entry) > 0 ? aws_vpc_endpoint.cockroachdb.dns_entry[0].dns_name : "N/A"
}

output "vpc_endpoint_state" {
  value = aws_vpc_endpoint.cockroachdb.state
}

output "privatelink_security_group_id" {
  value = aws_security_group.cockroachdb_privatelink.id
}
