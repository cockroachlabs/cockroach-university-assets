# CockroachDB PrivateLink Lab

## Quick Start

1. **Check AWS credentials:**
```bash
   ./scripts/check_aws.sh
```

2. **Initialize AWS infrastructure:**
```bash
   ./scripts/init_infrastructure.sh
```
   This will create:
   - VPC with DNS enabled
   - Private subnets for PrivateLink
   - NAT Gateway and routing
   - Security groups

3. **Load environment variables:**
```bash
   source .env
```

4. **Update SERVICE_NAME:**
   - Get the actual PrivateLink service name from CockroachDB Console
   - Update the SERVICE_NAME variable in `.env`
   - Re-source the environment: `source .env`

5. **Continue with the lab exercises**

## Files Structure
```
/root/privatelink-lab/
├── terraform/           # Terraform configurations
│   └── 01-infrastructure.tf
├── scripts/            # Helper scripts
│   ├── init_infrastructure.sh
│   ├── check_aws.sh
│   └── cleanup.sh
├── .env               # Environment variables (created after init)
└── README.md          # This file
```

## Troubleshooting

- If AWS credentials are not found, check environment variables
- If Terraform fails, check AWS permissions
- Run `terraform show` to see current infrastructure state

## Cleanup

To destroy all created AWS resources:
```bash
./scripts/cleanup.sh
```
