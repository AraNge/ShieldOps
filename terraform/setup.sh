#!/bin/bash

set -e

echo "Initializing Terraform..."
terraform init

echo "Applying Infrastructure..."
terraform apply -auto-approve
