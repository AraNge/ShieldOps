#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_NAME="shieldops-vm"
BOX_PATH="$HOME/Downloads/ubuntu2204.box"

echo "=== Uninstalling ShieldOps ==="

# Get VM IP if provided or from terraform output
if [ -n "$1" ]; then
    VM_IP="$1"
else
    cd "$SCRIPT_DIR/terraform" 2>/dev/null
    VM_IP=$(terraform output -raw vm_ip 2>/dev/null || echo "")
    
    if [ -z "$VM_IP" ]; then
        # Try to get IP from VirtualBox directly
        VM_IP=$(VBoxManage guestproperty get "$VM_NAME" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | awk '{print $2}')
    fi
    
    if [ -z "$VM_IP" ]; then
        echo "Could not detect VM IP automatically"
        read -p "Enter VM IP address (or press enter to skip VM cleanup): " VM_IP
    fi
fi

echo "⚠️  This will destroy everything including:"
echo "   - VM: $VM_NAME"
echo "   - iptables forwarding rules"
echo "   - Terraform state"
echo "   - Downloaded box file (optional)"
echo "   - Hostonly network vboxnet0 (optional)"
echo

read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# 1. Cleanup VM services (if IP is available and VM is running)
if [ -n "$VM_IP" ]; then
    echo "Cleaning up VM services on $VM_IP..."
    
    # Try SSH with both vagrant and ubuntu users
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no vagrant@$VM_IP "sudo rm -rf /home/vagrant/shieldops 2>/dev/null || true" 2>/dev/null; then
        echo "✓ Cleaned up /home/vagrant/shieldops"
    elif ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$VM_IP "sudo rm -rf /home/ubuntu/shieldops 2>/dev/null || true" 2>/dev/null; then
        echo "✓ Cleaned up /home/ubuntu/shieldops"
    else
        echo "⚠️  Could not SSH into VM (may already be powered off)"
    fi
fi

# 2. Destroy Terraform infrastructure
echo "Destroying Terraform infrastructure..."
cd "$SCRIPT_DIR/terraform" 2>/dev/null || cd "$SCRIPT_DIR"
if [ -f "terraform.tfstate" ]; then
    terraform destroy -auto-approve || echo "⚠️  Terraform destroy had issues, continuing cleanup..."
else
    echo "No Terraform state found, skipping terraform destroy"
fi

# 3. Remove VirtualBox VM
echo "Removing VirtualBox VM..."
if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    echo "Powering off and removing VM '$VM_NAME'..."
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    sleep 2
    VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || echo "⚠️  Could not delete VM"
else
    echo "VM '$VM_NAME' not found."
fi

# 4. Remove iptables forwarding rules
echo "Removing iptables rules..."

# Find your internet interface
INTERNET_IF=$(ip route | grep default | head -1 | awk '{print $5}')

if [ -n "$INTERNET_IF" ]; then
    echo "Found internet interface: $INTERNET_IF"
    
    # Remove NAT/Masquerade rule
    sudo iptables -t nat -D POSTROUTING -o "$INTERNET_IF" -j MASQUERADE 2>/dev/null && echo "✓ Removed MASQUERADE rule" || echo "ℹ️  MASQUERADE rule not found"
    
    # Remove forward rules
    sudo iptables -D FORWARD -i vboxnet0 -o "$INTERNET_IF" -j ACCEPT 2>/dev/null && echo "✓ Removed FORWARD rule (vboxnet0 -> $INTERNET_IF)" || echo "ℹ️  FORWARD rule not found"
    
    sudo iptables -D FORWARD -i "$INTERNET_IF" -o vboxnet0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && echo "✓ Removed FORWARD rule ($INTERNET_IF -> vboxnet0)" || echo "ℹ️  FORWARD rule not found"
    
    # Also try to remove any other vboxnet related rules
    sudo iptables -D FORWARD -i vboxnet0 -o "$INTERNET_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
else
    echo "⚠️  Could not find internet interface, skipping iptables cleanup"
fi

# Show remaining iptables rules (optional)
echo "Remaining iptables rules for vboxnet0:"
sudo iptables -L FORWARD -v -n | grep vboxnet0 || echo "None found"

# 5. Disable IP forwarding
echo "Disabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=0

# 6. Remove hostonly network (optional)
echo
read -p "Do you want to remove vboxnet0 hostonly network? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing vboxnet0..."
    
    # Stop DHCP server on the interface
    VBoxManage dhcpserver remove --ifname vboxnet0 2>/dev/null && echo "✓ Removed DHCP server" || echo "ℹ️  DHCP server not found"
    
    # Remove the hostonly interface
    VBoxManage hostonlyif remove vboxnet0 2>/dev/null && echo "✓ Removed vboxnet0" || echo "⚠️  Could not remove vboxnet0 (may be in use)"
else
    echo "Keeping vboxnet0"
fi

# 7. Optionally remove the downloaded box
echo
read -p "Do you want to delete the downloaded Ubuntu box file? ($BOX_PATH) (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f "$BOX_PATH" ]; then
        rm -f "$BOX_PATH"
        echo "✓ Removed box file"
    else
        echo "Box file not found"
    fi
fi

# 8. Clean up Terraform files (optional)
echo
read -p "Do you want to remove Terraform state files? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "$SCRIPT_DIR/terraform" 2>/dev/null || cd "$SCRIPT_DIR"
    rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
    rm -rf .terraform/
    echo "✓ Removed Terraform files"
fi

echo
echo "=== Cleanup Complete ==="
echo "✓ VM removed"
echo "✓ iptables rules cleaned"
echo "✓ IP forwarding disabled"
echo
echo "To verify cleanup:"
echo "  - Run: VBoxManage list vms (should not show $VM_NAME)"
echo "  - Run: sudo iptables -L FORWARD -v -n | grep vboxnet0 (should show nothing)"