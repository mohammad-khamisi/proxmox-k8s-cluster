# Full clone of the cloud-init template (e.g. 8000 template-rocky-10-proxmox).
resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = var.description
  tags        = var.tags
  on_boot     = true

  clone {
    vm_id        = var.template_id
    node_name    = var.template_node
    full         = true
    datastore_id = var.datastore_id
  }

  # prepare-node.sh installs and starts the agent.
  agent {
    enabled = var.agent_enabled
    timeout = "15m"
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
  }

  bios          = var.bios
  scsi_hardware = var.scsi_hardware

  # UEFI: the EFI vars disk (with the template's boot entries) comes with the
  # clone and is deliberately not managed here, so it is never replaced by an
  # empty one.

  boot_order = [var.disk_interface]

  # The template's disk on the same interface, grown to disk_gb.
  disk {
    datastore_id = var.datastore_id
    interface    = var.disk_interface
    iothread     = startswith(var.disk_interface, "virtio")
    discard      = "on"
    size         = var.disk_gb
  }

  network_device {
    model   = var.network_model
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  serial_device {}

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ip_cidr
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_account {
      username = var.user_account.username
      keys     = var.user_account.keys
      password = var.user_account.password
    }
  }

  lifecycle {
    # Cloud-init only applies on first boot; don't recreate on key changes.
    ignore_changes = [initialization[0].user_account, efi_disk]
  }
}
