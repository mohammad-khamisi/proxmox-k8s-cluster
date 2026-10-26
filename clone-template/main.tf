# Full clones of the template. Only the network is managed here: BIOS/EFI
# disk, disks, controller, CPU, memory and the rest of cloud-init come from the
# template unchanged.
resource "proxmox_cloned_vm" "this" {
  for_each = var.vms

  id        = each.value.vm_id
  node_name = coalesce(each.value.node, var.node_name)
  name      = each.key

  clone = {
    source_vm_id     = var.template_id
    source_node_name = var.template_node != "" ? var.template_node : null
    full             = true
    target_datastore = var.datastore != "" ? var.datastore : null
  }

  # Network cards listed in 'networks'; others stay as in the template.
  network = length(each.value.networks) == 0 ? null : {
    for slot, nic in each.value.networks : slot => {
      bridge      = nic.bridge
      model       = nic.model
      tag         = nic.vlan_id
      mac_address = nic.mac_address
      firewall    = nic.firewall
      mtu         = nic.mtu
    }
  }

  # Lets 'terraform destroy' remove the VMs even if they are running and have
  # no guest agent.
  stop_on_destroy = true
}

# ---------------------------------------------------------------------------
# Cloud-init IP/DNS. proxmox_cloned_vm doesn't manage cloud-init, so the
# values are written to each new VM's config through the Proxmox API. The VMs
# are still stopped, so they apply on first boot. 'curl' is built into Linux,
# macOS and Windows 10+.
# ---------------------------------------------------------------------------
locals {
  cloud_init_params = {
    for name, vm in var.vms : name => concat(
      [
        for slot, n in vm.networks :
        "ipconfig${trimprefix(slot, "net")}=ip=${n.ip}${n.gateway != null ? ",gw=${n.gateway}" : ""}"
        if n.ip != null
      ],
      length(coalesce(vm.dns_servers, var.dns_servers)) > 0 ? ["nameserver=${join(" ", coalesce(vm.dns_servers, var.dns_servers))}"] : [],
      coalesce(vm.dns_domain, var.dns_domain, "-") != "-" ? ["searchdomain=${coalesce(vm.dns_domain, var.dns_domain)}"] : [],
    )
  }
}

resource "terraform_data" "cloud_init_network" {
  for_each = { for name, params in local.cloud_init_params : name => params if length(params) > 0 }

  # Written again when the VM is replaced or a value changes.
  triggers_replace = [proxmox_cloned_vm.this[each.key].id, each.value]

  provisioner "local-exec" {
    command = join(" ", concat(
      ["curl --fail -sS -X PUT", var.proxmox_insecure ? "-k" : ""],
      ["-H \"Authorization: PVEAPIToken=${var.proxmox_api_token}\""],
      [for p in each.value : "--data-urlencode \"${p}\""],
      ["\"${trimsuffix(var.proxmox_endpoint, "/")}/api2/json/nodes/${coalesce(var.vms[each.key].node, var.node_name)}/qemu/${proxmox_cloned_vm.this[each.key].id}/config\""],
    ))
  }
}
