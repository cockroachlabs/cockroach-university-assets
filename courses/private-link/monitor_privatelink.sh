#!/bin/bash

echo "================================================================"
echo "CockroachDB PrivateLink Monitor"
echo "================================================================"
echo "Time: $(date)"
echo ""

# AWS Account Info
echo "AWS Account Information:"
echo "----------------------------------------------------------------"
aws sts get-caller-identity --output table

# Infrastructure Status
echo ""
echo "Infrastructure Status:"
echo "----------------------------------------------------------------"
echo "VPC ID: ${VPC_ID}"
echo "VPC CIDR: ${VPC_CIDR}"
echo "Region: ${AWS_REGION}"
echo "Subnets: ${SUBNET_IDS}"
echo "Security Group: ${SECURITY_GROUP_ID}"

# DNS Configuration
echo ""
echo "DNS Configuration:"
echo "----------------------------------------------------------------"
VPC_DNS_ENABLED=$(aws ec2 describe-vpc-attribute --vpc-id ${VPC_ID} --attribute enableDnsSupport --query 'EnableDnsSupport.Value' --output text)
VPC_DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute --vpc-id ${VPC_ID} --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value' --output text)
echo "DNS Support: ${VPC_DNS_ENABLED} $([ "$VPC_DNS_ENABLED" = "true" ] && echo "✓" || echo "✗")"
echo "DNS Hostnames: ${VPC_DNS_HOSTNAMES} $([ "$VPC_DNS_HOSTNAMES" = "true" ] && echo "✓" || echo "✗")"

# VPC Endpoints
echo ""
echo "VPC Endpoints:"
echo "----------------------------------------------------------------"
ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State]' \
  --output text 2>/dev/null)

if [ -n "$ENDPOINTS" ]; then
  echo "$ENDPOINTS" | while read id service state; do
    echo "Endpoint: $id"
    echo "  Service: $service"
    echo "  State: $state"
    echo ""
  done
else
  echo "No VPC endpoints found (expected for simulation)"
fi

# Simulated Metrics
echo ""
echo "Simulated PrivateLink Metrics (Production):"
echo "----------------------------------------------------------------"
echo "Endpoint State: Available"
echo "ENI Status: In-service"
echo "DNS Resolution: Private IP (10.0.x.x)"
echo "Active Connections: N/A (no real cluster)"
echo "Bytes In/Out: N/A"
echo "Endpoint Availability: 100%"

# Cost Estimate
echo ""
echo "Cost Tracking:"
echo "----------------------------------------------------------------"
echo "Estimated runtime: Check AWS billing console"
echo "NAT Gateway: ~\$0.045/hour"
echo "VPC Endpoint: ~\$0.01/hour (when created)"
echo ""
echo "Remember to run ./scripts/cleanup.sh when finished!"

echo ""
echo "================================================================"
echo "Monitor Complete"
echo "================================================================"
```

## 6. `.gitignore`
```
# AWS Credentials - NEVER commit these!
aws-credentials.sh
*.pem
*.key

# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
.terraform.lock.hcl

# Environment files
.env

# OS files
.DS_Store
Thumbs.db
