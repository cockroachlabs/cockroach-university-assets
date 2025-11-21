#!/bin/bash

echo "Checking AWS Setup..."
echo "===================="

# Check for credentials
if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "✓ AWS credentials found in environment"
else
    echo "✗ No AWS credentials found"
    echo ""
    echo "Please configure your AWS credentials first:"
    echo "  Option 1: Run ./setup-credentials.sh"
    echo "  Option 2: Edit and source aws-credentials.sh"
    echo "  Option 3: Export AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    exit 1
fi

# Test credentials
echo ""
echo "Testing credentials..."
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo "✓ AWS credentials are valid"
    echo ""
    aws sts get-caller-identity --output table
else
    echo "✗ AWS credentials are not valid"
    echo "Please check your Access Key ID and Secret Access Key"
    exit 1
fi

echo ""
echo "AWS CLI version:"
aws --version
