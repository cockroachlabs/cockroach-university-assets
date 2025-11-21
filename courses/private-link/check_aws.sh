#!/bin/bash

echo "Checking AWS Setup..."
echo "===================="

# Check for credentials
if [ -n "${INSTRUQT_AWS_ACCOUNT_AWS_ACCESS_KEY_ID:-}" ]; then
    echo "✓ Instruqt AWS credentials found"
    export AWS_ACCESS_KEY_ID="${INSTRUQT_AWS_ACCOUNT_AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${INSTRUQT_AWS_ACCOUNT_AWS_SECRET_ACCESS_KEY}"
    export AWS_SESSION_TOKEN="${INSTRUQT_AWS_ACCOUNT_AWS_SESSION_TOKEN:-}"
elif [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "✓ AWS credentials found in environment"
else
    echo "✗ No AWS credentials found"
    echo ""
    echo "Looking for Instruqt variables:"
    env | grep INSTRUQT | grep AWS || echo "  None found"
    exit 1
fi

# Test credentials
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo "✓ AWS credentials are valid"
    aws sts get-caller-identity --output table
else
    echo "✗ AWS credentials are not valid"
    exit 1
fi

echo ""
echo "AWS CLI version:"
aws --version
