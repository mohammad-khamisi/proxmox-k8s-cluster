output "vm_id" {
  value = proxmox_cloned_vm.this.id
}

output "vm_name" {
  value = var.vm_name
}
