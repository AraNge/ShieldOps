#!/bin/bash

set -e

BOX_PATH="$HOME/Downloads/ubuntu2204.box"
VM_NAME="shieldops-vm"

if [ ! -f "$BOX_PATH" ]; then
    echo "Image not found locally. Downloading image to $BOX_PATH..."
    curl -L -o "$BOX_PATH" "https://app.vagrantup.com/generic/boxes/ubuntu2204/versions/4.3.12/providers/virtualbox.box"
else
    echo "Image already exists at $BOX_PATH. Skipping download."
fi

# Create hostonly network if it doesn't exist
if ! VBoxManage list hostonlyifs | grep -q "vboxnet0"; then
    echo "Network vboxnet0 not found. Creating..."
    VBoxManage hostonlyif create
    VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
    VBoxManage dhcpserver add --ifname vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0 --lowerip 192.168.56.100 --upperip 192.168.56.200 --enable
else
    echo "Network vboxnet0 already exists."
    # Ensure DHCP is enabled
    VBoxManage dhcpserver modify --ifname vboxnet0 --enable 2>/dev/null || \
    VBoxManage dhcpserver add --ifname vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0 --lowerip 192.168.56.100 --upperip 192.168.56.200 --enable
fi

# Remove existing VM if present
if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    echo "Existing VM '$VM_NAME' detected. Forcibly removing..."
    VBoxManage controlvm "$VM_NAME" poweroff 2>/dev/null || true
    VBoxManage unregistervm "$VM_NAME" --delete
else
    echo "Existing VM '$VM_NAME' not found. No cleanup required."
fi

# NETWORK SETUP
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null

# Detect internet interface more reliably
INTERNET_IF=$(ip route get 8.8.8.8 | grep -o 'dev [[:alnum:]]\+' | awk '{print $2}' | head -n1)
echo "Detected internet interface: $INTERNET_IF"

# Flush everything and apply clean rules
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

sudo iptables -t nat -A POSTROUTING -o "$INTERNET_IF" -j MASQUERADE
sudo iptables -A FORWARD -i vboxnet0 -o "$INTERNET_IF" -j ACCEPT
sudo iptables -A FORWARD -i "$INTERNET_IF" -o vboxnet0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Disable host firewalls temporarily
echo "Disabling host firewalls (if present)..."
sudo ufw disable 2>/dev/null || true
sudo systemctl stop firewalld 2>/dev/null || true
sudo systemctl stop ufw 2>/dev/null || true

export TF_VAR_home_dir=$HOME

echo "Terraform init + apply..."
terraform init
terraform apply -auto-approve

echo "✅ VM created. Waiting for boot..."
sleep 25