Minimal usage

module "example" {
  source    = "./modules/proxmox_vm"
  providers = { proxmox = proxmox.pve1 }

  name      = "Example-VM"
  node_name = "pve-1"
  vm_id     = 200
  # That’s it. Defaults will create:
  # - CPU: 2 cores, 1 socket, numa enabled
  # - Memory: 2048 MB
  # - Disks: 1x 30GB boot disk on scsi0, path "vm-200-disk-0", datastore = init_datastore_id
  # - Network: 1x virtio NIC on vmbr0 with auto MAC
  # - Cloud-init: DHCP on IPv4/IPv6 by default, username "gabriel" with your SSH key
}

Common overrides

module "example_custom" {
  source    = "./modules/proxmox_vm"
  providers = { proxmox = proxmox.pve1 }

  name      = "Example-Custom"
  node_name = "pve-1"
  vm_id     = 201

  cpu_cores        = 4
  memory_dedicated = 4096

  # Override boot disk defaults (still just provide minimal info)
  boot_disk_size_gb       = 50
  boot_disk_datastore_id  = "local-lvm-2"

  # Static IP via cloud-init (example address space)
  init_ipv4_address = "192.0.2.50/24"
  init_ipv4_gateway = "192.0.2.1"
}