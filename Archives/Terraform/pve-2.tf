
module "docker_2" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve2 }
  name             = "Docker-2"
  node_name        = "pve-2"
  vm_id            = 101
  cpu_cores        = 4
  cpu_hotplugged   = 4
  memory_dedicated = 5120
  disks = [
    { size = 30, interface = "scsi0", path_in_datastore = "vm-101-disk-0" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:B7:B9:6B" }
  ]
  init_ipv4_address = "192.168.15.11/24"
  init_ipv4_gateway = "192.168.15.1"
  init_dns_servers  = ["192.168.15.1"]
  startup = {
    order      = 2
    up_delay   = -1
    down_delay = -1
  }
  usbs = [
    {
      host    = "10c4:ea60"
      mapping = null
      usb3    = false
    }
  ]
}

module "ubuntu_cloud_2" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve2 }
  name             = "Ubuntu-Cloud-2"
  node_name        = "pve-2"
  vm_id            = 100
  template         = true
  started          = false
  cpu_cores        = 4
  memory_dedicated = 3072
  disks = [
    { size = 10, interface = "scsi0", path_in_datastore = "base-100-disk-0" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:D6:96:20" }
  ]
  init_dns_servers = ["192.168.15.1"]
}
module "dns_2" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve2 }
  name             = "DNS-2"
  node_name        = "pve-2"
  vm_id            = 102
  cpu_cores        = 2
  memory_dedicated = 2048
  disks = [
    { size = 30, interface = "scsi0", path_in_datastore = "vm-102-disk-0" },
    { size = 30, interface = "scsi1", path_in_datastore = "vm-102-disk-1" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:FF:0E:85" }
  ]
  init_ipv4_address = "192.168.15.5/24"
  init_ipv4_gateway = "192.168.15.1"
  init_dns_servers  = ["192.168.15.1"]
  startup = {
    order      = 1
    up_delay   = -1
    down_delay = -1
  }
}

# RKE2 worker on pve-2
module "k8s_worker_2" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve2 }
  name             = "k8s-worker-2"
  node_name        = "pve-2"
  vm_id            = 122
  cpu_cores        = 4
  memory_dedicated = 5120
  # Clone from Ubuntu-Cloud-2 template on pve-2 (vm_id 100)
  clone_vm_id     = 100
  clone_node_name = "pve-2"
  # 30GB boot disk is default via module; leaving disks empty to use defaults
  init_ipv4_address = "192.168.15.22/24"
  init_ipv4_gateway = "192.168.15.1"
  init_dns_servers  = ["192.168.15.1"]
  tags              = ["k8s", "worker"]
}


