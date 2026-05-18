terraform {
  required_providers {
    virtualbox = {
      source  = "terra-farm/virtualbox"
      version = "0.2.2-alpha.1"
    }
  }
}

provider "virtualbox" {}

variable "home_dir" {
  type = string
}

resource "virtualbox_vm" "shieldops_vm" {
  name   = "shieldops-vm"
  image  = "${var.home_dir}/Downloads/ubuntu2204.box"
  cpus   = 4
  memory = "8192 mib"

  network_adapter {
    type           = "hostonly"
    host_interface = "vboxnet0"
  }

  # Uncomment this block if host-only still has issues (provides reliable internet)
  # network_adapter {
  #   type = "nat"
  # }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "vagrant"
      password = "vagrant"
      host     = self.network_adapter[0].ipv4_address
      timeout  = "5m"
    }

    inline = [
      "echo '=== Waiting for network ==='",
      "sleep 25",

      "sudo ip link set eth0 up 2>/dev/null || true",

      "echo '=== Fixing routing and DNS ==='",
      "sudo ip route del default 2>/dev/null || true",
      "sudo ip route add default via 192.168.56.1 dev eth0 || true",

      "echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf > /dev/null",
      "echo 'nameserver 8.8.4.4' | sudo tee -a /etc/resolv.conf > /dev/null",
      "echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf > /dev/null",

      "echo '=== Testing connectivity ==='",
      "ping -c 3 8.8.8.8 || echo 'Ping 8.8.8.8 failed'",
      "ping -c 3 google.com || echo 'DNS failed'",

      "echo '=== Updating packages ==='",
      "for i in {1..6}; do sudo apt-get update -y && break || sleep 10; done",

      "echo '=== Installing Docker ==='",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release",

      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",

      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",

      "sudo apt-get update -y",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",

      "sudo systemctl enable --now docker",
      "sudo usermod -aG docker vagrant",

      "echo '=== SUCCESS: Docker installed ==='",
      "sudo docker --version"
    ]
  }
}

output "vm_ip" {
  value = virtualbox_vm.shieldops_vm.network_adapter[0].ipv4_address
}

output "vm_name" {
  value = virtualbox_vm.shieldops_vm.name
}