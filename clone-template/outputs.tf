output "vms" {
  description = "Created VMs: ID, node and IP per network slot"
  value = {
    for name, vm in var.vms : name => {
      vm_id   = proxmox_cloned_vm.this[name].id
      node    = coalesce(vm.node, var.node_name)
      disk_gb = coalesce(vm.disk_gb, var.disk_gb)
      ips     = { for slot, n in vm.networks : slot => n.ip if n.ip != null }
    }
  }
}
