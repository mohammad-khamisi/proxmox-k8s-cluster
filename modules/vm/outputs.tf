output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = var.name
}

output "ip" {
  value = split("/", var.ip_cidr)[0]
}
