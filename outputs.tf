output "jumpbox" {
  description = "SSH to the jumpbox; kubectl is ready there"
  value       = "ssh ${var.vm_user}@${local.jumpbox_ip}"
}

output "masters" {
  value = { for i, m in var.masters : m.name => local.master_ips[i] }
}

output "workers" {
  value = { for i, w in var.workers : w.name => local.worker_ips[i] }
}

output "api_server" {
  value = "https://${local.api_endpoint}:6443"
}

output "rke2_version" {
  value = var.rke2_version
}

output "kubeconfig_copy_command" {
  description = "Copy the kubeconfig to your own machine through the jumpbox"
  value       = "scp ${var.vm_user}@${local.jumpbox_ip}:.kube/config ./kubeconfig"
}

output "vm_user_console_password" {
  description = "Password of vm_user for the Proxmox noVNC console (terraform output -raw vm_user_console_password)"
  value       = random_password.vm_user.result
  sensitive   = true
}

output "rke2_token" {
  description = "Cluster join token, for adding nodes later"
  value       = random_password.rke2_token.result
  sensitive   = true
}
