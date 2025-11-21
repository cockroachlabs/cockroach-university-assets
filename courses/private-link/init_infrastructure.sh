#!/bin/bash
set -e

echo "========================================"
echo "Initializing AWS Infrastructure"
echo "========================================"

# Check for AWS credentials
echo "Checking AWS credentials..."

# Try different credential sources
if [ -n "${INSTRUQT_AWS_ACCOUNT_AWS_ACCESS_KEY_ID:-}" ]; then
    echo "Using Instruqt-provided credentials"
    export AWS_ACCESS_KEY_ID="${INSTRUQT_AWS_ACCOUNT_AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${INSTRUQT_AWS_ACCOUNT_AWS_SECRET_ACCESS_KEY}"
    export AWS_SESSION_TOKEN="${INSTRUQT_AWS_ACCOUNT_AWS_SESSION_TOKEN:-}"
elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "Using existing AWS credentials"
else
    echo "ERROR: No AWS credentials found!"
    echo "Please ensure AWS credentials are configured."
    exit 1
fi

# Verify credentials work
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "ERROR: AWS credentials are not valid"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: ${AWS_ACCOUNT_ID}"

# Set region
export AWS_REGION="${AWS_REGION:-us-east-1}"
echo "AWS Region: ${AWS_REGION}"

# Generate unique suffix for resources
RESOURCE_SUFFIX="${USER:-learner}-$(date +%s | tail -c 4)"
echo "Resource suffix: ${RESOURCE_SUFFIX}"

# Navigate to terraform directory
cd /root/privatelink-lab/terraform

# Create terraform.tfvars
cat > terraform.tfvars << EOF
aws_region      = "${AWS_REGION}"
resource_suffix = "${RESOURCE_SUFFIX}"
EOF

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
terraform init

# Plan infrastructure
echo ""
echo "Planning infrastructure..."
terraform plan -out=tfplan

# Apply infrastructure
echo ""
echo "Creating infrastructure (this may take 2-3 minutes)..."
terraform apply tfplan

# Export outputs to environment file
echo ""
echo "Exporting environment variables..."

# Get Terraform outputs
export VPC_ID=$(terraform output -raw vpc_id)
export VPC_CIDR=$(terraform output -raw vpc_cidr)
export SUBNET_IDS=$(terraform output -raw subnet_ids_string)
export SECURITY_GROUP_ID=$(terraform output -raw security_group_id)
export AWS_REGION=$(terraform output -raw aws_region)

# Set cluster-related variables
export CLUSTER_NAME="free-tier-14"
export CLUSTER_FQDN="${CLUSTER_NAME}.aws-${AWS_REGION}.cockroachlabs.cloud"

# Note: SERVICE_NAME needs to be obtained from CockroachDB Console
export SERVICE_NAME="com.amazonaws.vpce.${AWS_REGION}.vpce-svc-REPLACE_WITH_ACTUAL"

# Create environment file
cat > /root/privatelink-lab/.env << ENV_EOF
# AWS Infrastructure
export AWS_REGION="${AWS_REGION}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
export VPC_ID="${VPC_ID}"
export VPC_CIDR="${VPC_CIDR}"
export SUBNET_IDS="${SUBNET_IDS}"
export SECURITY_GROUP_ID="${SECURITY_GROUP_ID}"
export RESOURCE_SUFFIX="${RESOURCE_SUFFIX}"

# CockroachDB Configuration
export CLUSTER_NAME="${CLUSTER_NAME}"
export CLUSTER_FQDN="${CLUSTER_FQDN}"

# PrivateLink Service (UPDATE WITH ACTUAL VALUE FROM COCKROACHDB CONSOLE)
export SERVICE_NAME="${SERVICE_NAME}"

echo "Environment variables loaded from /root/privatelink-lab/.env"
ENV_EOF

# Source the environment
source /root/privatelink-lab/.env

echo ""
echo "========================================"
echo "Infrastructure Setup Complete!"
echo "========================================"
echo ""
echo "Created resources:"
echo "  VPC ID: ${VPC_ID}"
echo "  VPC CIDR: ${VPC_CIDR}"
echo "  Subnet IDs: ${SUBNET_IDS}"
echo "  Security Group: ${SECURITY_GROUP_ID}"
echo ""
echo "IMPORTANT: Update SERVICE_NAME in .env with the actual"
echo "           value from CockroachDB Console before proceeding."
echo ""
echo "To load environment variables in new terminals:"
echo "  source /root/privatelink-lab/.env"
echo ""
