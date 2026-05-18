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
sshpass -p "vagrant" ssh -o ServerAliveInterval=60 -o StrictHostKeyChecking=no vagrant@$VM_IP "
    cd /home/vagrant/shieldops/wazuh && 
    chmod +x setup.sh && 
    ./setup.sh
"

# Install Jenkins
echo "Installing Jenkins on the VM..."
sshpass -p "vagrant" ssh -o ServerAliveInterval=60 -o StrictHostKeyChecking=no vagrant@$VM_IP "
    cd /home/vagrant/shieldops/jenkins && 
    chmod +x setup.sh && 
    ./setup.sh
"


echo "Setting up Ngrok tunnel for Jenkins (ShieldOps Security Scan)..."

sshpass -p "vagrant" ssh -o ServerAliveInterval=60 -o StrictHostKeyChecking=no vagrant@$VM_IP '
    cd /home/vagrant/shieldops/jenkins

    # Install ngrok
    if ! command -v ngrok &> /dev/null; then
        echo "Installing ngrok..."
        curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
        | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
        && echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
        | sudo tee /etc/apt/sources.list.d/ngrok.list \
        && sudo apt update \
        && sudo apt install ngrok
    fi

    # Add authtoken from host environment variable
    echo "🔑 Configuring Ngrok authtoken..."
    ngrok config add-authtoken '"$NGROK_AUTHTOKEN"'

    # Kill any old tunnel
    pkill ngrok 2>/dev/null || true

    # Start ngrok
    echo "Starting Ngrok tunnel..."
    nohup ngrok http 8080 --name "ShieldOps-Security-Scan" > /tmp/ngrok.log 2>&1 &
    sleep 5

    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o "https://[^\"]*" | head -n1)
    echo "Ngrok Public URL: $NGROK_URL"
'

# Get final Ngrok URL
NGROK_URL=$(sshpass -p "vagrant" ssh -o StrictHostKeyChecking=no vagrant@$VM_IP "
    sleep 3
    curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^\"]*' | head -n1
" 2>/dev/null || echo "Not available yet")

echo ""
echo "ShieldOps is ready!"
echo "=================================================="
echo "VM IP            : $VM_IP"
echo "Jenkins Local    : http://$VM_IP:8080"
echo "Jenkins Public   : ${NGROK_URL}"
echo "Wazuh            : http://$VM_IP:55000"
echo "=================================================="
echo "Ngrok Name       : ShieldOps-Security-Scan"
echo ""
echo "GitHub Webhook URL:"
echo "${NGROK_URL}/generic-webhook-trigger/invoke?token=shieldops-trigger"
echo ""