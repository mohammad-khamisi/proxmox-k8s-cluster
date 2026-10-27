# ---------------------------------------------------------------------------
# Per-VM settings, with the global defaults filled in.
# ---------------------------------------------------------------------------
locals {
  global_gateway = var.gateway != "" ? var.gateway : null

  vms = {
    for vm in var.vms : vm.name => {
      vm_id   = vm.vm_id
      node    = coalesce(vm.node, var.node_name)
      disk_gb = coalesce(vm.disk_gb, var.disk_gb)

      networks = merge(
        {
          net0 = {
            bridge      = coalesce(vm.bridge, var.network_bridge)
            model       = coalesce(vm.model, var.network_model)
            vlan_id     = vm.vlan_id != null ? vm.vlan_id : var.vlan_id
            mac_address = vm.mac_address
            firewall    = vm.firewall
            mtu         = vm.mtu
            ip          = vm.ip
            gateway     = vm.gateway != null ? vm.gateway : local.global_gateway
          }
        },
        {
          for slot, n in vm.extra_networks : slot => {
            bridge      = coalesce(n.bridge, var.network_bridge)
            model       = coalesce(n.model, var.network_model)
            vlan_id     = n.vlan_id
            mac_address = n.mac_address
            firewall    = n.firewall
            mtu         = n.mtu
            ip          = n.ip
            gateway     = n.gateway
          }
        },
      )

      dns_servers = vm.dns_servers != null ? vm.dns_servers : var.dns_servers
      dns_domain  = vm.dns_domain != null ? vm.dns_domain : var.dns_domain
    }
  }

  # Cloud-init values per VM: ipconfigN for every card with an IP, DNS.
  cloud_init_params = {
    for name, vm in local.vms : name => concat(
      [
        for slot, n in vm.networks :
        "ipconfig${trimprefix(slot, "net")}=${n.ip == "dhcp" ? "ip=dhcp" : join(",", compact([
          "ip=${strcontains(n.ip, "/") ? n.ip : "${n.ip}/${var.ip_prefix}"}",
          n.gateway != null ? "gw=${n.gateway}" : "",
        ]))}"
        if n.ip != null
      ],
      length(vm.dns_servers) > 0 ? ["nameserver=${join(" ", vm.dns_servers)}"] : [],
      vm.dns_domain != "" ? ["searchdomain=${vm.dns_domain}"] : [],
    )
  }

}

# ---------------------------------------------------------------------------
# Full clones of the template. Only the network and the boot disk size are
# managed here: BIOS/EFI disk, controller, CPU, memory and the rest of
# cloud-init come from the template unchanged.
# ---------------------------------------------------------------------------
resource "proxmox_cloned_vm" "this" {
  for_each = local.vms

  id        = each.value.vm_id
  node_name = each.value.node
  name      = each.key

  clone = {
    source_vm_id     = var.template_id
    source_node_name = var.template_node != "" ? var.template_node : var.node_name
    full             = true
    target_datastore = var.datastore != "" ? var.datastore : null
  }

  network = {
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
      size_gb      = each.value.disk_gb
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
# values are written to each new VM's config through the Proxmox API while
# the VM is still stopped; then the VM is started, and they apply on first
# boot.
#
# The API calls use curl (built into Linux, macOS and Windows 10+) with its
# options in a config file, so the command line has no quotes for cmd.exe /
# PowerShell / sh to mangle. The files hold the API token and are kept in
# .terraform/ (not committed).
# ---------------------------------------------------------------------------
locals {
  api_base = "${trimsuffix(var.proxmox_endpoint, "/")}/api2/json/nodes"

  curl_common = join("", [
    "silent\nshow-error\nfail\n",
    var.proxmox_insecure ? "insecure\n" : "",
    "header = \"Authorization: PVEAPIToken=${var.proxmox_api_token}\"\n",
  ])
}

resource "local_sensitive_file" "set_cloud_init" {
  for_each = { for name, params in local.cloud_init_params : name => params if length(params) > 0 }

  filename        = "${path.module}/.terraform/curl/${each.key}-cloud-init.txt"
  file_permission = "0600"
  content = join("", concat(
    [local.curl_common, "request = \"PUT\"\n"],
    [for p in each.value : "data-urlencode = \"${p}\"\n"],
    ["url = \"${local.api_base}/${local.vms[each.key].node}/qemu/${proxmox_cloned_vm.this[each.key].id}/config\"\n"],
  ))
}

resource "local_sensitive_file" "start" {
  for_each = var.start_vms ? local.vms : {}

  filename        = "${path.module}/.terraform/curl/${each.key}-start.txt"
  file_permission = "0600"
  content = join("", [
    local.curl_common,
    "request = \"POST\"\n",
    "url = \"${local.api_base}/${each.value.node}/qemu/${proxmox_cloned_vm.this[each.key].id}/status/start\"\n",
  ])
}

resource "terraform_data" "configure" {
  for_each = local.vms

  # Run again when the VM is replaced or a cloud-init value changes.
  triggers_replace = [proxmox_cloned_vm.this[each.key].id, local.cloud_init_params[each.key]]

  provisioner "local-exec" {
    command = contains(keys(local_sensitive_file.set_cloud_init), each.key) ? "curl -K ${try(local_sensitive_file.set_cloud_init[each.key].filename, "")}" : "echo no cloud-init network settings"
  }

  # A VM that is already running (e.g. after an IP change) just keeps
  # running; restart it to apply the new IP.
  provisioner "local-exec" {
    command    = var.start_vms ? "curl -K ${try(local_sensitive_file.start[each.key].filename, "")}" : "echo not starting"
    on_failure = continue
  }
}
