#!/bin/bash

echo "Testing lab setup..."
echo "===================="

# Check directories
[ -d "/root/privatelink-lab/terraform" ] && echo "✓ Terraform directory exists" || echo "✗ Terraform directory missing"
[ -d "/root/privatelink-lab/scripts" ] && echo "✓ Scripts directory exists" || echo "✗ Scripts directory missing"

# Check files
[ -f "/root/privatelink-lab/terraform/01-infrastructure.tf" ] && echo "✓ Infrastructure template exists" || echo "✗ Infrastructure template missing"
[ -f "/root/privatelink-lab/scripts/init_infrastructure.sh" ] && echo "✓ Init script exists" || echo "✗ Init script missing"
[ -f "/root/privatelink-lab/scripts/check_aws.sh" ] && echo "✓ Check AWS script exists" || echo "✗ Check AWS script missing"
[ -f "/root/privatelink-lab/scripts/cleanup.sh" ] && echo "✓ Cleanup script exists" || echo "✗ Cleanup script missing"

# Check tools
command -v terraform > /dev/null && echo "✓ Terraform installed" || echo "✗ Terraform not installed"
command -v aws > /dev/null && echo "✓ AWS CLI installed" || echo "✗ AWS CLI not installed"
command -v jq > /dev/null && echo "✓ jq installed" || echo "✗ jq not installed"

echo ""
echo "Setup complete! Learners should run:"
echo "  1. cd /root/privatelink-lab"
echo "  2. ./scripts/check_aws.sh"
echo "  3. ./scripts/init_infrastructure.sh"
