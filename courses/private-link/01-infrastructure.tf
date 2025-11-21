terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "resource_suffix" {
  description = "Unique suffix for resources to avoid conflicts"
  type        = string
  default     = ""
}

# Create VPC with DNS enabled for PrivateLink
resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "cockroachdb-privatelink-vpc${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
    Lab         = "PrivateLink"
    Environment = "Training"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "lab_igw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name = "cockroachdb-igw${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  }
}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Private Subnet 1 (for PrivateLink endpoint)
resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "cockroachdb-private-1${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
    Type = "Private"
  }
}

# Private Subnet 2 (for PrivateLink endpoint - HA)
resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "cockroachdb-private-2${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
    Type = "Private"
  }
}

# Public Subnet (for NAT Gateway)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "cockroachdb-public${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
    Type = "Public"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "cockroachdb-nat-eip${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "lab_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "cockroachdb-nat${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  }

  depends_on = [aws_internet_gateway.lab_igw]
}

# Route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_igw.id
  }

  tags = {
    Name = "cockroachdb-public-rt${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  }
}

# Route table for private subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.lab_nat.id
  }

  tags = {
    Name = "cockroachdb-private-rt${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  }
}

# Route table associations
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rta_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

# Security group
resource "aws_security_group" "lab_sg" {
  name        = "cockroachdb-lab-sg${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  description = "Security group for CockroachDB PrivateLink lab"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "cockroachdb-lab-sg${var.resource_suffix != "" ? "-${var.resource_suffix}" : ""}"
  }
}

# Outputs for use in the exercise
output "vpc_id" {
  value       = aws_vpc.lab_vpc.id
  description = "VPC ID for PrivateLink endpoint"
}

output "vpc_cidr" {
  value       = aws_vpc.lab_vpc.cidr_block
  description = "VPC CIDR block"
}

output "private_subnet_ids" {
  value       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  description = "Private subnet IDs for PrivateLink endpoint"
}

output "subnet_ids_string" {
  value       = "${aws_subnet.private_subnet_1.id},${aws_subnet.private_subnet_2.id}"
  description = "Comma-separated subnet IDs"
}

output "security_group_id" {
  value       = aws_security_group.lab_sg.id
  description = "Security group ID"
}

output "aws_region" {
  value       = var.aws_region
  description = "AWS region"
}
