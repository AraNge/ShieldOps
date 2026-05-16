terraform {
  required_providers {
    virtualbox = {
      source  = "terra-farm/virtualbox"
      version = "0.2.2-alpha.1"
    }
  }
}

provider "virtualbox" {}

resource "virtualbox_vm" "shieldops_vm" {
  name   = "shieldops-vm"
  image  = "https://app.vagrantup.com/generic/boxes/ubuntu2204/versions/4.3.12/providers/virtualbox.box"

  cpus   = 2
  memory = "2048 mib"

  network_adapter {
    type           = "hostonly"
    host_interface = "vboxnet0"
  }
}
