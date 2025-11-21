# CockroachDB PrivateLink Lab

## Prerequisites

You will need:
- An AWS account with administrative access
- AWS credentials (Access Key ID and Secret Access Key)
- Permissions to create VPCs, subnets, NAT gateways, and PrivateLink endpoints

## Quick Start

### Step 1: Configure AWS Credentials

**Option A: Interactive Setup (Recommended)**
```bash
cd /root/privatelink-lab
./setup-credentials.sh
```

This will prompt you for:
- AWS Access Key ID
- AWS Secret Access Key
- AWS Session Token (optional)
- AWS Region (default: us-east-1)

**Option B: Manual Export**
```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 2: Load Credentials

If you used Option A:
```bash
source aws-credentials.sh
```

### Step 3: Verify AWS Credentials
```bash
./scripts/check_aws.sh
```

You should see:
```
✓ AWS credentials found in environment
✓ AWS credentials are valid
```

### Step 4: Initialize AWS Infrastructure
```bash
./scripts/init_infrastructure.sh
```

This will create (takes 2-3 minutes):
- VPC with DNS enabled
- Private subnets for PrivateLink
- NAT Gateway and routing
- Security groups

### Step 5: Load Environment Variables
```bash
source .env
```

### Step 6: Update SERVICE_NAME
- Get the actual PrivateLink service name from CockroachDB Console
- Edit `.env` and update the SERVICE_NAME variable
- Re-source: `source .env`

### Step 7: Continue with Lab Exercises

Follow the remaining lab instructions to create the PrivateLink endpoint and test connectivity.

## Getting AWS Credentials

### Creating AWS Access Keys

1. Sign in to AWS Console
2. Go to **IAM** → **Users** → Your username
3. Click **Security credentials** tab
4. Under **Access keys**, click **Create access key**
5. Select **Command Line Interface (CLI)**
6. Download or copy your credentials
7. ⚠️ **Keep these secure!** Never commit them to version control

### Required AWS Permissions

Your AWS user/role needs permissions to create:
- VPCs and Subnets
- Internet Gateways and NAT Gateways
- Route Tables
- Security Groups
- Elastic IPs
- VPC Endpoints (for PrivateLink)

A user with `PowerUserAccess` or `AdministratorAccess` will work.

## Security Notes

⚠️ **IMPORTANT**: 
- Never commit `aws-credentials.sh` to version control
- The `.gitignore` file excludes this automatically
- After the lab, delete your access keys if you created them specifically for this exercise
- Consider using AWS CloudShell or temporary credentials when possible
- Always run the cleanup script when finished to avoid ongoing charges

## Files Structure
```
/root/privatelink-lab/
├── terraform/                    # Terraform configurations
│   └── 01-infrastructure.tf
├── scripts/                      # Helper scripts
│   ├── init_infrastructure.sh
│   ├── check_aws.sh
│   └── cleanup.sh
├── setup-credentials.sh          # Interactive credential setup
├── aws-credentials.sh            # Your credentials (created by setup-credentials.sh)
├── .env                         # Environment variables (created after init)
├── test_setup.sh                # Verify lab setup
└── README.md                    # This file
```

## Troubleshooting

### "No AWS credentials found"
- Make sure you've run: `source aws-credentials.sh`
- Verify credentials are in environment: `echo $AWS_ACCESS_KEY_ID`
- Run the check script: `./scripts/check_aws.sh`

### "AWS credentials are not valid"
- Verify your Access Key ID and Secret Access Key are correct
- Check if your AWS user has required permissions
- Try using AWS CLI directly: `aws sts get-caller-identity`

### Terraform fails with permission errors
- Your AWS user needs VPC creation permissions
- Check IAM policies attached to your user
- Verify you're using the correct AWS region

### "terraform init" fails
- Check your internet connectivity
- Verify Terraform is installed: `terraform version`
- Try running from the terraform directory: `cd terraform && terraform init`

## Cleanup

⚠️ **Important**: Always clean up AWS resources to avoid ongoing charges!
```bash
./scripts/cleanup.sh
```

This will destroy all created AWS infrastructure including:
- VPC and all subnets
- NAT Gateway and Elastic IP
- Security groups
- Route tables
- PrivateLink endpoint (if created)

## Cost Estimate

Running this lab will incur AWS charges:
- **NAT Gateway**: ~$0.045/hour + $0.045/GB data processed
- **VPC Endpoint**: ~$0.01/hour + $0.01/GB data processed
- **Elastic IP**: Free when attached, $0.005/hour when unattached

**Estimated cost for 2-hour lab**: $0.15 - $0.30

**Important**: Remember to run the cleanup script when finished to stop charges!

## Additional Resources

- [AWS PrivateLink Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [CockroachDB Cloud Private Connectivity](https://www.cockroachlabs.com/docs/cockroachcloud/network-authorization)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review the AWS CloudFormation/Terraform error messages
3. Verify your AWS permissions
4. Contact your course instructor or Cockroach Labs support
