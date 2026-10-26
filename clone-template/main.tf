# Full clone of the template. Only the network is managed here: BIOS/EFI disk,
# disks, controller, CPU, memory and the rest of cloud-init come from the
# template unchanged.
resource "proxmox_cloned_vm" "this" {
  id        = var.vm_id
  node_name = var.node_name
  name      = var.vm_name

  clone = {
    source_vm_id     = var.template_id
    source_node_name = var.template_node != "" ? var.template_node : null
    full             = true
    target_datastore = var.datastore != "" ? var.datastore : null
  }

  # Network cards listed in network_devices; others stay as in the template.
  network = length(var.network_devices) == 0 ? null : {
    for slot, nic in var.network_devices : slot => {
      bridge      = nic.bridge
      model       = nic.model
      tag         = nic.vlan_id
      mac_address = nic.mac_address
      firewall    = nic.firewall
      mtu         = nic.mtu
    }
  }

  # Lets 'terraform destroy' remove the VM even if it is running and has no
  # guest agent.
  stop_on_destroy = true
}

# ---------------------------------------------------------------------------
# Cloud-init IP/DNS. proxmox_cloned_vm doesn't manage cloud-init, so the
# values are written to the new VM's config through the Proxmox API. The VM
# is still stopped, so they apply on its first boot. 'curl' is built into
# Linux, macOS and Windows 10+.
# ---------------------------------------------------------------------------
locals {
  cloud_init_params = concat(
    [
      for slot, c in var.ip_configs :
      "ipconfig${trimprefix(slot, "net")}=ip=${c.address}${c.gateway != null ? ",gw=${c.gateway}" : ""}"
    ],
    length(var.dns_servers) > 0 ? ["nameserver=${join(" ", var.dns_servers)}"] : [],
    var.dns_domain != "" ? ["searchdomain=${var.dns_domain}"] : [],
  )

  vm_config_url = "${trimsuffix(var.proxmox_endpoint, "/")}/api2/json/nodes/${var.node_name}/qemu/${proxmox_cloned_vm.this.id}/config"
}

resource "terraform_data" "cloud_init_network" {
  count = length(local.cloud_init_params) > 0 ? 1 : 0

  # Written again when the VM is replaced or a value changes.
  triggers_replace = [proxmox_cloned_vm.this.id, local.cloud_init_params]

  provisioner "local-exec" {
    command = join(" ", concat(
      ["curl --fail -sS -X PUT", var.proxmox_insecure ? "-k" : ""],
      ["-H \"Authorization: PVEAPIToken=${var.proxmox_api_token}\""],
      [for p in local.cloud_init_params : "--data-urlencode \"${p}\""],
      ["\"${local.vm_config_url}\""],
    ))
  }
}
