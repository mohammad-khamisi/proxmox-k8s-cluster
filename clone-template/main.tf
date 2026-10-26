# Full clones of the template. Only the network and the boot disk size are
# managed here: BIOS/EFI disk, controller, CPU, memory and the rest of
# cloud-init come from the template unchanged.
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

  # The cloned boot disk, grown to disk_gb.
  disk = {
    (var.disk_interface) = {
      datastore_id = var.datastore != "" ? var.datastore : null
      size_gb      = coalesce(each.value.disk_gb, var.disk_gb)
    }
  }

  # Started below, once cloud-init has its IP/DNS.
  started = false

  # Lets 'terraform destroy' remove the VMs even if they are running and have
  # no guest agent.
  stop_on_destroy = true

  lifecycle {
    # The VMs are started outside this resource; don't stop them again.
    ignore_changes = [started]
  }
}

# ---------------------------------------------------------------------------
# Cloud-init IP/DNS. proxmox_cloned_vm doesn't manage cloud-init, so the
# values are written to each new VM's config through the Proxmox API. The VMs
# are still stopped, so they apply on first boot; then the VMs are started.
# 'curl' is built into Linux, macOS and Windows 10+.
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

  curl = join(" ", [
    "curl --fail -sS",
    var.proxmox_insecure ? "-k" : "",
    "-H \"Authorization: PVEAPIToken=${var.proxmox_api_token}\"",
  ])
}

resource "terraform_data" "configure" {
  for_each = var.vms

  # Run again when the VM is replaced or a cloud-init value changes.
  triggers_replace = [proxmox_cloned_vm.this[each.key].id, local.cloud_init_params[each.key]]

  provisioner "local-exec" {
    command = length(local.cloud_init_params[each.key]) == 0 ? "echo no cloud-init network settings" : join(" ", concat(
      [local.curl, "-X PUT"],
      [for p in local.cloud_init_params[each.key] : "--data-urlencode \"${p}\""],
      ["\"${trimsuffix(var.proxmox_endpoint, "/")}/api2/json/nodes/${coalesce(each.value.node, var.node_name)}/qemu/${proxmox_cloned_vm.this[each.key].id}/config\""],
    ))
  }

  # A VM that is already running (e.g. after an IP change) just keeps
  # running; restart it to apply the new IP.
  provisioner "local-exec" {
    command    = var.start_vms ? "${local.curl} -X POST \"${trimsuffix(var.proxmox_endpoint, "/")}/api2/json/nodes/${coalesce(each.value.node, var.node_name)}/qemu/${proxmox_cloned_vm.this[each.key].id}/status/start\"" : "echo not starting"
    on_failure = continue
  }
}
