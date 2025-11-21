#!/bin/bash

echo "Cleaning up AWS infrastructure..."
cd /root/privatelink-lab/terraform

if [ -f terraform.tfstate ]; then
    terraform destroy -auto-approve
    echo "Infrastructure destroyed"
else
    echo "No infrastructure to destroy"
fi
