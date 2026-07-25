variable "name" {}
variable "node_name" {}
variable "vm_id" {}

variable "scsi_hardware" { default = "virtio-scsi-single" }
variable "started" { default = true }
variable "tablet_device" { default = true }
variable "tags" { default = [] }
variable "template" { default = false }
variable "keyboard_layout" { default = null }
variable "migrate" { default = null }
variable "on_boot" { default = null }
variable "reboot" { default = null }
variable "reboot_after_update" { default = null }
variable "stop_on_destroy" { default = null }
variable "timeout_clone" { default = null }
variable "timeout_create" { default = null }
variable "timeout_migrate" { default = null }
variable "timeout_reboot" { default = null }
variable "timeout_shutdown_vm" { default = null }
variable "timeout_start_vm" { default = null }
variable "timeout_stop_vm" { default = null }

variable "agent_enabled" { default = true }
variable "agent_timeout" { default = "0m" }
variable "agent_trim" { default = false }
variable "agent_type" { default = null }

variable "cpu_cores" { default = 2 }
variable "cpu_sockets" { default = 1 }
variable "cpu_type" { default = "x86-64-v2-AES" }
variable "cpu_numa" { default = true }
variable "cpu_limit" { default = 0 }
variable "cpu_hotplugged" { default = null }
variable "cpu_units" { default = 1024 }
variable "cpu_flags" { default = [] }
variable "cpu_architecture" { default = null }
variable "cpu_affinity" { default = null }

variable "memory_dedicated" { default = 2048 }
variable "memory_floating" { default = null }
# When true, configure the ballooning device to allow online RAM changes without enabling dynamic reclaim.
# By default we set floating to dedicated, which enables hotplug but does not change behavior unless you adjust values.
variable "memory_enable_hotplug" { default = true }
variable "memory_hugepages" { default = null }
variable "memory_keep_hugepages" { default = false }
variable "memory_shared" { default = 0 }

variable "disks" {
  type    = list(any)
  default = []
}


# Optional explicit render order for disks (by interface key, e.g., "scsi0").
# When null, disks are rendered in sorted(interface) order.
variable "disk_render_order" {
  type    = list(string)
  default = null
}


# If no custom disks are provided, a single boot disk will be created with these defaults
variable "boot_disk_size_gb" { default = 30 }
variable "boot_disk_datastore_id" { default = null }
variable "boot_disk_interface" { default = "scsi0" }
variable "boot_disk_path" { default = null }

variable "network_devices" {
  type    = list(any)
  default = []
}

# If no NICs are provided, one NIC will be created with these defaults
variable "default_nic_bridge" { default = "vmbr0" }
variable "default_nic_model" { default = "virtio" }

variable "init_datastore_id" { default = "local-lvm" }
variable "init_interface" { default = "ide0" }
variable "init_meta_data_file_id" { default = null }
variable "init_network_data_file_id" { default = null }
variable "init_type" { default = null }
variable "init_user_data_file_id" { default = null }
variable "init_vendor_data_file_id" { default = null }

variable "init_dns_domain" { default = "gwebs.ca" }
variable "init_dns_servers" {
  type    = list(string)
  default = ["192.168.10.1"]
}

variable "init_ipv4_address" { default = "dhcp" }
variable "init_ipv4_gateway" { default = null }
variable "init_ipv6_address" { default = "dhcp" }
variable "init_ipv6_gateway" { default = null }

variable "init_user_username" { default = "gabriel" }
variable "init_user_keys" {
  type    = list(string)
  default = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpRej6BHMw/6qH5zmyzE4mI6skbjSowAeqUPBpOP8sR gabri@Gwebs-PC-1"]
}
variable "init_user_password" { default = null }

variable "os_type" { default = "l26" }

variable "startup" { default = null }
variable "hostpcis" { default = [] }
variable "usbs" { default = [] }

# Optional cloning configuration. When clone_vm_id is set, the VM will be cloned from
# the specified template or source VM.
variable "clone_vm_id" { default = null }
variable "clone_node_name" { default = null }
variable "clone_datastore_id" { default = null }
variable "clone_retries" { default = null }
variable "clone_full" { default = true }
