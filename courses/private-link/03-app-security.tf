resource "aws_security_group" "app_to_cockroachdb" {
  name        = "app-to-cockroachdb-${var.resource_suffix}"
  description = "Application access to CockroachDB via PrivateLink"
  vpc_id      = var.vpc_id

  egress {
    description = "CockroachDB SQL via PrivateLink"
    from_port   = 26257
    to_port     = 26257
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
  }

  egress {
    description = "HTTPS for other services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "App-to-CockroachDB"
    Type = "Application"
  }
}

output "app_security_group_id" {
  value = aws_security_group.app_to_cockroachdb.id
}
