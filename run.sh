#!/bin/bash

echo "Launching ShieldOps..."

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Terraform (VM Creation)
echo "Creating VM via Terraform..."
cd "$SCRIPT_DIR/terraform"
chmod +x setup.sh
./setup.sh

# Get the VM IP address
VM_IP=$(terraform output -raw vm_ip)
echo "✅ VM created: $VM_IP"

# Copying files to the VM
echo "📁 Copying ShieldOps to the VM..."
scp -r "$SCRIPT_DIR" ubuntu@$VM_IP:/home/ubuntu/

# Jenkins on the VM
echo "🚀 Installing Jenkins on the VM..."
ssh ubuntu@$VM_IP "cd /home/ubuntu/shieldops/jenkins && chmod +x setup.sh && ./setup.sh"

# Wazuh on the VM
echo "🛡️ Installing Wazuh on the VM..."
ssh ubuntu@$VM_IP "cd /home/ubuntu/shieldops/wazuh && chmod +x setup.sh && ./setup.sh"

echo ""
echo "✅ ShieldOps is ready!"
echo "Jenkins: http://$VM_IP:8080"
echo "Wazuh: http://$VM_IP:55000"
echo ""