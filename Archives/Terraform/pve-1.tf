
module "nas_1" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "NAS-1"
  node_name        = "pve-1"
  vm_id            = 104
  cpu_cores        = 4
  memory_dedicated = 10240
  disk_render_order = ["scsi5", "scsi0", "scsi2", "scsi3", "scsi4"]
  # Disks documented below and managed
  disks = [
    # Boot disk on scsi0
    { size = 30, interface = "scsi0", path_in_datastore = "vm-104-disk-0", ssd = true },
    # ZFS-backed raw disks (passthrough) — managed but not backed up
    { size = 3726, interface = "scsi2", path_in_datastore = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0PFZTDV" },
    { size = 3726, interface = "scsi3", path_in_datastore = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0ZZLF4D" },
    { size = 3726, interface = "scsi4", path_in_datastore = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K0RKY2R4" },
    { size = 3726, interface = "scsi5", path_in_datastore = "/dev/disk/by-id/ata-WDC_WD40EFRX-68N32N0_WD-WCC7K3RFKDKV" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:81:72:3A" }
  ]
  init_ipv4_address = "192.168.10.12/24"
  init_ipv4_gateway = "192.168.10.1"
  startup = {
    order      = 2
    up_delay   = 30
    down_delay = -1
  }
}

module "ubuntu_cloud" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "Ubuntu-Cloud"
  node_name        = "pve-1"
  vm_id            = 101
  template         = true
  started          = false
  cpu_cores        = 4
  memory_dedicated = 4096
  disks = [
    { size = 10, interface = "scsi0", path_in_datastore = "base-101-disk-0" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:83:F1:A0" }
  ]
  init_dns_servers = ["192.168.10.5"]
}


module "dns_1" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "DNS-1"
  node_name        = "pve-1"
  vm_id            = 102
  cpu_cores        = 2
  memory_dedicated = 2048
  disks = [
    { size = 30, interface = "scsi0", path_in_datastore = "vm-102-disk-0" },
    { size = 30, interface = "scsi1", path_in_datastore = "vm-102-disk-1" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:F1:1B:37" }
  ]
  init_ipv4_address = "192.168.10.5/24"
  init_ipv4_gateway = "192.168.10.1"
  startup = {
    order      = 1
    up_delay   = 20
    down_delay = -1
  }
}


module "plex_1" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "Plex-1"
  node_name        = "pve-1"
  vm_id            = 103
  cpu_cores        = 8
  memory_dedicated = 4096
  disks = [
    { size = 30, interface = "scsi0", path_in_datastore = "vm-103-disk-0" },
    { size = 50, interface = "scsi2", path_in_datastore = "vm-103-disk-2" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:20:FA:3B" }
  ]
  init_ipv4_address = "192.168.10.13/24"
  init_ipv4_gateway = "192.168.10.1"
  startup = {
    order      = 3
    up_delay   = -1
    down_delay = -1
  }
  hostpcis = [
    {
      device   = "hostpci0"
      id       = "0000:06:00"
      mapping  = null
      mdev     = null
      pcie     = false
      rom_file = null
      rombar   = true
      xvga     = false
    }
  ]
}


module "docker_1" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "Docker-1"
  node_name        = "pve-1"
  vm_id            = 105
  cpu_cores        = 6
  memory_dedicated = 10240
  disks = [
    { size = 40, interface = "scsi0", path_in_datastore = "vm-105-disk-1", datastore_id = "local-lvm-2" },
    { size = 50, interface = "scsi1", path_in_datastore = "vm-105-disk-0", datastore_id = "local-lvm-2" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:4E:7E:73" }
  ]
  init_ipv4_address = "192.168.10.11/24"
  init_ipv4_gateway = "192.168.10.1"
  init_dns_servers  = ["192.168.10.5"]
  startup = {
    order      = 4
    up_delay   = -1
    down_delay = -1
  }
}


module "satisfactory" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "Satisfactory"
  node_name        = "pve-1"
  vm_id            = 106
  started          = true
  cpu_cores        = 4
  cpu_type         = "host"
  memory_dedicated = 8192
  disks = [
    { size = 40, interface = "scsi0", path_in_datastore = "vm-106-disk-0" }
  ]
  network_devices = [
    { mac_address = "BC:24:11:BF:F5:9C" }
  ]
  init_ipv4_address = "192.168.10.14/24"
  init_ipv4_gateway = "192.168.10.1"
  startup = {
    order      = 10
    up_delay   = -1
    down_delay = -1
  }
}

# # RKE2 cluster nodes on pve-1
module "k8s_master_1" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "k8s-master-1"
  node_name        = "pve-1"
  vm_id            = 120
  cpu_cores        = 2
  memory_dedicated = 4096
  # Clone from Ubuntu-Cloud template on pve-1 (vm_id 101)
  clone_vm_id     = 101
  clone_node_name = "pve-1"
  # 30GB boot disk is default via module; leaving disks empty to use defaults
  init_ipv4_address = "192.168.10.20/24"
  init_ipv4_gateway = "192.168.10.1"
  init_dns_servers  = ["192.168.10.5"]
  tags              = ["k8s", "master"]
}

module "k8s_worker_1" {
  source           = "./modules/proxmox_vm"
  providers        = { proxmox = proxmox.pve1 }
  name             = "k8s-worker-1"
  node_name        = "pve-1"
  vm_id            = 121
  cpu_cores        = 6
  memory_dedicated = 10240
  # Clone from Ubuntu-Cloud template on pve-1 (vm_id 101)
  clone_vm_id     = 101
  clone_node_name = "pve-1"
  # 30GB boot disk is default via module; leaving disks empty to use defaults
  init_ipv4_address = "192.168.10.21/24"
  init_ipv4_gateway = "192.168.10.1"
  init_dns_servers  = ["192.168.10.5"]
  tags              = ["k8s", "worker"]
}
