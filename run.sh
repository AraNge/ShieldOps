#!/bin/bash
set -e

echo "🚀 Launching ShieldOps..."

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

# Terraform VM Creation
echo "Creating VM via Terraform..."
cd "$TERRAFORM_DIR"

chmod +x setup.sh
./setup.sh

# Get VM IP Address
echo "Fetching VM IP..."
VM_IP=$(terraform output -raw vm_ip 2>/dev/null || echo "")

if [ -z "$VM_IP" ]; then
    echo "⚠️  Could not get VM IP from terraform output. Trying alternative method..."
    VM_IP=$(VBoxManage guestproperty get shieldops-vm /VirtualBox/GuestInfo/Net/0/V4/IP | awk '{print $2}')
fi

if [ -z "$VM_IP" ] || [ "$VM_IP" = "value:" ]; then
    echo "❌ Failed to get VM IP. Please check if VM is running."
    VBoxManage showvminfo shieldops-vm | grep -E "Name|NIC|IP"
    exit 1
fi

echo "✅ VM IP: $VM_IP"

# Wait for SSH to be ready
echo "⏳ Waiting for SSH to be ready on VM..."
for i in {1..30}; do
    if sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 vagrant@$VM_IP "echo SSH ready" &> /dev/null; then
        echo "✅ SSH is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 8
done

# Copy files to VM
echo "Copying ShieldOps files to the VM..."
sshpass -p "vagrant" scp -o StrictHostKeyChecking=no -r "$SCRIPT_DIR" vagrant@$VM_IP:/home/vagrant/shieldops/

# Install Wazuh
echo "Installing Wazuh on the VM..."
sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@$VM_IP "
    cd /home/vagrant/shieldops/wazuh && 
    chmod +x setup.sh && 
    ./setup.sh
"

# Install Jenkins
echo "Installing Jenkins on the VM..."
sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@$VM_IP "
    cd /home/vagrant/shieldops/jenkins && 
    chmod +x setup.sh && 
    ./setup.sh
"

echo ""
echo "ShieldOps is ready!"
echo "Jenkins → http://$VM_IP:8080"
echo "Wazuh   → http://$VM_IP:55000"
echo ""
echo "VM IP: $VM_IP"
echo "SSH Access: ssh vagrant@$VM_IP"