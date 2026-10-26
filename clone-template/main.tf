# Full clone of the template, nothing else: BIOS/EFI disk, disks, controller,
# network, CPU, memory and cloud-init all come from the template unchanged.
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

  # Lets 'terraform destroy' remove the VM even if it is running and has no
  # guest agent.
  stop_on_destroy = true
}
