output "vms" {
  description = "Created VMs: ID, node, disk and IP per network slot"
  value = {
    for name, vm in local.vms : name => {
      vm_id   = proxmox_cloned_vm.this[name].id
      node    = vm.node
      disk_gb = vm.disk_gb
      ips     = { for slot, n in vm.networks : slot => n.ip if n.ip != null }
    }
  }
}
