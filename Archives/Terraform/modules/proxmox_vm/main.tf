locals {
  effective_disks = length(var.disks) > 0 ? var.disks : [
    {
      size              = var.boot_disk_size_gb
      interface         = var.boot_disk_interface
      path_in_datastore = coalesce(var.boot_disk_path, "vm-${var.vm_id}-disk-0")
      datastore_id      = coalesce(var.boot_disk_datastore_id, var.init_datastore_id)
    }
  ]

  # Key disks by interface to ensure stable addressing regardless of list order
  effective_disks_by_interface = { for d in local.effective_disks : d.interface => d }
  # Deterministic render order for disk blocks: sort by interface key (e.g., scsi0, scsi1, ...)
  sorted_disk_keys = sort(keys(local.effective_disks_by_interface))
  # Build a LIST based on explicit order when provided; otherwise sorted by interface
  effective_disk_order = var.disk_render_order != null ? var.disk_render_order : local.sorted_disk_keys
  ordered_disks_list = [for k in local.effective_disk_order : local.effective_disks_by_interface[k] if contains(keys(local.effective_disks_by_interface), k)]


  effective_network_devices = length(var.network_devices) > 0 ? var.network_devices : [
    {
      bridge = var.default_nic_bridge
      model  = var.default_nic_model
    }
  ]
}

resource "proxmox_virtual_environment_vm" "this" {
  name                = var.name
  node_name           = var.node_name
  scsi_hardware       = var.scsi_hardware
  started             = var.started
  tablet_device       = var.tablet_device
  tags                = var.tags
  template            = var.template
  vm_id               = var.vm_id
  keyboard_layout     = var.keyboard_layout
  migrate             = var.migrate
  on_boot             = var.on_boot
  reboot              = var.reboot
  reboot_after_update = var.reboot_after_update
  stop_on_destroy     = var.stop_on_destroy
  timeout_clone       = var.timeout_clone
  timeout_create      = var.timeout_create
  timeout_migrate     = var.timeout_migrate
  timeout_reboot      = var.timeout_reboot
  timeout_shutdown_vm = var.timeout_shutdown_vm
  timeout_start_vm    = var.timeout_start_vm
  timeout_stop_vm     = var.timeout_stop_vm

  dynamic "clone" {
    for_each = var.clone_vm_id != null ? [1] : []
    content {
      vm_id        = var.clone_vm_id
      node_name    = coalesce(var.clone_node_name, var.node_name)
      datastore_id = var.clone_datastore_id
      retries      = var.clone_retries
      full         = var.clone_full
    }
  }

  lifecycle {
    ignore_changes = [
      keyboard_layout,
      migrate,
      on_boot,
      reboot,
      reboot_after_update,
      started,
      stop_on_destroy,
      timeout_clone,
      timeout_create,
      timeout_migrate,
      timeout_reboot,
      timeout_shutdown_vm,
      timeout_start_vm,
      timeout_stop_vm,
      agent,
      # Prevent disk reindex/moves caused by provider list ordering changes
      disk[0].interface,
      disk[1].interface,
      disk[2].interface,
      disk[3].interface,
      disk[4].interface,
      disk[5].interface,
      disk[6].interface,
      disk[7].interface,
      disk[0].path_in_datastore,
      disk[1].path_in_datastore,
      disk[2].path_in_datastore,
      disk[3].path_in_datastore,
      disk[4].path_in_datastore,
      disk[5].path_in_datastore,
      disk[6].path_in_datastore,
      disk[7].path_in_datastore,
      # Keep ignoring storage format fields managed externally
      disk[0].datastore_id,
      disk[1].datastore_id,
      disk[2].datastore_id,
      disk[3].datastore_id,
      disk[4].datastore_id,
      disk[5].datastore_id,
      disk[6].datastore_id,
      disk[7].datastore_id,
      disk[0].file_format,
      disk[1].file_format,
      disk[2].file_format,
      disk[3].file_format,
      disk[4].file_format,
      disk[5].file_format,
      disk[6].file_format,
      disk[7].file_format,
    ]
  }

  agent {
    enabled = var.agent_enabled
    timeout = var.agent_timeout
    trim    = var.agent_trim
    type    = var.agent_type
  }

  cpu {
    cores        = var.cpu_cores
    sockets      = var.cpu_sockets
    type         = var.cpu_type
    numa         = var.cpu_numa
    limit        = var.cpu_limit
    # Only set hotplugged when explicitly provided to avoid exceeding maxcpus during online updates
    hotplugged   = var.cpu_hotplugged
    units        = var.cpu_units
    flags        = var.cpu_flags
    architecture = var.cpu_architecture
    affinity     = var.cpu_affinity
  }

  memory {
    dedicated      = var.memory_dedicated
    floating       = var.memory_enable_hotplug ? coalesce(var.memory_floating, var.memory_dedicated) : var.memory_floating
    hugepages      = var.memory_hugepages
    keep_hugepages = var.memory_keep_hugepages
    shared         = var.memory_shared
  }

  dynamic "disk" {
    for_each = local.ordered_disks_list
    content {
      # Merge user disk with defaults
      # Only size and interface are required from user
      # All other fields defaulted
      # For raw passthrough devices, set raw=true in the disk map to avoid datastore_id/file_format
      aio               = lookup(disk.value, "aio", "io_uring")
      # Determine passthrough automatically when path points to /dev/* unless raw is explicitly set
      backup            = lookup(disk.value, "backup", (try(disk.value.raw, startswith(lookup(disk.value, "path_in_datastore", ""), "/dev/")) ? false : true))
      cache             = lookup(disk.value, "cache", "none")
      datastore_id      = (try(disk.value.raw, startswith(lookup(disk.value, "path_in_datastore", ""), "/dev/")) ? null : lookup(disk.value, "datastore_id", var.init_datastore_id))
      discard           = lookup(disk.value, "discard", "ignore")
      file_format       = (try(disk.value.raw, startswith(lookup(disk.value, "path_in_datastore", ""), "/dev/")) ? null : lookup(disk.value, "file_format", "raw"))
      file_id           = lookup(disk.value, "file_id", null)
      interface         = disk.value["interface"]
      iothread          = lookup(disk.value, "iothread", true)
      path_in_datastore = lookup(disk.value, "path_in_datastore", null)
      replicate         = lookup(disk.value, "replicate", true)
      serial            = lookup(disk.value, "serial", null)
      size              = disk.value["size"]
      ssd               = lookup(disk.value, "ssd", (try(disk.value.raw, startswith(lookup(disk.value, "path_in_datastore", ""), "/dev/")) ? false : true))
    }
  }

  dynamic "network_device" {
    for_each = local.effective_network_devices
    content {
      # Merge user network device with defaults
      # mac_address is optional; Proxmox can auto-generate when null
      bridge       = lookup(network_device.value, "bridge", "vmbr0")
      model        = lookup(network_device.value, "model", "virtio")
      mac_address  = lookup(network_device.value, "mac_address", null)
      firewall     = lookup(network_device.value, "firewall", true)
      enabled      = lookup(network_device.value, "enabled", true)
      disconnected = lookup(network_device.value, "disconnected", false)
      mtu          = lookup(network_device.value, "mtu", 0)
      queues       = lookup(network_device.value, "queues", 0)
      rate_limit   = lookup(network_device.value, "rate_limit", 0)
      trunks       = lookup(network_device.value, "trunks", null)
      vlan_id      = lookup(network_device.value, "vlan_id", 0)
    }
  }

  initialization {
    datastore_id         = var.init_datastore_id
    interface            = var.init_interface
    meta_data_file_id    = var.init_meta_data_file_id
    network_data_file_id = var.init_network_data_file_id
    type                 = var.init_type
    user_data_file_id    = var.init_user_data_file_id
    vendor_data_file_id  = var.init_vendor_data_file_id

    dns {
      domain  = var.init_dns_domain
      servers = var.init_dns_servers
    }

    ip_config {
      ipv4 {
        address = var.init_ipv4_address
        gateway = var.init_ipv4_gateway
      }
      ipv6 {
        address = var.init_ipv6_address
        gateway = var.init_ipv6_gateway
      }
    }

    user_account {
      username = var.init_user_username
      keys     = var.init_user_keys
      password = var.init_user_password
    }
  }

  operating_system {
    type = var.os_type
  }

  dynamic "startup" {
    for_each = var.startup != null ? [var.startup] : []
    content {
      order      = startup.value.order
      up_delay   = startup.value.up_delay
      down_delay = startup.value.down_delay
    }
  }

  dynamic "hostpci" {
    for_each = var.hostpcis
    content {
      device   = hostpci.value.device
      id       = hostpci.value.id
      mapping  = hostpci.value.mapping
      mdev     = hostpci.value.mdev
      pcie     = hostpci.value.pcie
      rom_file = hostpci.value.rom_file
      rombar   = hostpci.value.rombar
      xvga     = hostpci.value.xvga
    }
  }

  dynamic "usb" {
    for_each = var.usbs
    content {
      host    = usb.value.host
      mapping = usb.value.mapping
      usb3    = usb.value.usb3
    }
  }
}
