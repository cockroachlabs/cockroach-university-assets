#!/bin/bash
# Interactive AWS Credentials Setup Script

echo "=========================================="
echo "AWS Credentials Setup"
echo "=========================================="
echo ""
echo "You will need:"
echo "  - AWS Access Key ID"
echo "  - AWS Secret Access Key"
echo "  - AWS Region (default: us-east-1)"
echo ""
echo "Get these from: AWS Console > IAM > Users > Security Credentials"
echo ""

# Prompt for credentials
read -p "Enter your AWS Access Key ID: " ACCESS_KEY
read -sp "Enter your AWS Secret Access Key: " SECRET_KEY
echo ""
read -p "Enter your AWS Session Token (press Enter to skip): " SESSION_TOKEN
read -p "Enter your AWS Region [us-east-1]: " REGION
REGION=${REGION:-us-east-1}

# Create credentials file
cat > /root/privatelink-lab/aws-credentials.sh << EOF
#!/bin/bash
# AWS Credentials - Generated $(date)
# DO NOT commit this file to version control!

export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"
export AWS_SESSION_TOKEN="${SESSION_TOKEN}"
export AWS_REGION="${REGION}"
export AWS_DEFAULT_REGION="${REGION}"

echo "AWS credentials loaded!"
echo "Region: \${AWS_REGION}"
EOF

chmod +x /root/privatelink-lab/aws-credentials.sh

echo ""
echo "✓ Credentials saved to: /root/privatelink-lab/aws-credentials.sh"
echo ""
echo "To load your credentials in any terminal:"
echo "  source /root/privatelink-lab/aws-credentials.sh"
echo ""
echo "Next steps:"
echo "  1. source /root/privatelink-lab/aws-credentials.sh"
echo "  2. ./scripts/check_aws.sh"
echo "  3. ./scripts/init_infrastructure.sh"
