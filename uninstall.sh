#!/bin/bash

echo "Uninstalling ShieldOps..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Get VM IP
if [ -n "$1" ]; then
    VM_IP="$1"
else
    cd "$SCRIPT_DIR/terraform" 2>/dev/null
    VM_IP=$(terraform output -raw vm_ip 2>/dev/null)
    
    if [ -z "$VM_IP" ]; then
        read -p "Enter VM IP address: " VM_IP
    fi
fi

echo "This will destroy everything on $VM_IP"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Cleanup VM services
echo "Cleaning up VM..."
ssh ubuntu@$VM_IP "sudo rm -rf /home/ubuntu/shieldops"

# Destroy Terraform infrastructure
echo "Destroying infrastructure..."
cd "$SCRIPT_DIR/terraform"
terraform destroy -auto-approve

echo "✅ ShieldOps removed!"