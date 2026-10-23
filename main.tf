locals {
  template_node = var.template_node != "" ? var.template_node : null

  master_ips = [for m in var.masters : split("/", m.ip)[0]]
  worker_ips = [for w in var.workers : split("/", w.ip)[0]]
  jumpbox_ip = split("/", var.jumpbox.ip)[0]

  first_master_ip = local.master_ips[0]
  api_endpoint    = var.api_endpoint != "" ? var.api_endpoint : local.first_master_ip
  tls_san         = distinct(concat(compact([var.api_endpoint]), local.master_ips, [for m in var.masters : m.name]))

  # kubectl matching the cluster: v1.36.5+rke2r1 -> v1.36.5
  kubectl_version = split("+", var.rke2_version)[0]

  # Every host, for /etc/hosts on all VMs.
  hosts = merge(
    { for i, m in var.masters : m.name => local.master_ips[i] },
    { for i, w in var.workers : w.name => local.worker_ips[i] },
    { (var.jumpbox.name) = local.jumpbox_ip },
  )

  # The jumpbox's own key is allowed on every VM, so it can SSH to the nodes.
  vm_user_account = {
    username = var.vm_user
    keys     = concat(var.ssh_public_keys, [trimspace(tls_private_key.jumpbox.public_key_openssh)])
    password = random_password.vm_user.result
  }
}

# Shared secret the nodes use to join the cluster.
resource "random_password" "rke2_token" {
  length  = 48
  special = false
}

# Console password for vm_user (Proxmox noVNC console).
resource "random_password" "vm_user" {
  length  = 20
  special = false
}

# A cloned disk cannot be smaller than the template's.
resource "terraform_data" "validate_inputs" {
  lifecycle {
    precondition {
      condition = alltrue([
        for r in [var.master_resources, var.worker_resources, var.jumpbox_resources] :
        r.disk_gb >= var.template_disk_gb
      ])
      error_message = "disk_gb of masters, workers and jumpbox must be >= template_disk_gb (${var.template_disk_gb} GB)."
    }
  }
}

# SSH key the jumpbox uses to reach the cluster nodes.
resource "tls_private_key" "jumpbox" {
  algorithm = "ED25519"
}

# ---------------------------------------------------------------------------
# VMs (full clones of the template)
# ---------------------------------------------------------------------------
module "jumpbox" {
  source = "./modules/vm"

  name           = var.jumpbox.name
  vm_id          = var.jumpbox.vm_id
  node_name      = coalesce(var.jumpbox.node, var.proxmox_node)
  description    = "Jumpbox for the RKE2 cluster (managed by Terraform)"
  tags           = ["terraform", "jumpbox"]
  cores          = var.jumpbox_resources.cores
  memory_mb      = var.jumpbox_resources.memory_mb
  disk_gb        = var.jumpbox_resources.disk_gb
  cpu_type       = var.cpu_type
  bios           = var.bios
  scsi_hardware  = var.scsi_hardware
  network_model  = var.network_model
  datastore_id   = var.vm_datastore
  template_id    = var.template_id
  template_node  = local.template_node
  disk_interface = var.template_disk_interface
  bridge         = var.network_bridge
  vlan_id        = var.vlan_id
  ip_cidr        = var.jumpbox.ip
  gateway        = var.gateway
  dns_servers    = var.dns_servers
  dns_domain     = var.dns_domain
  agent_enabled  = var.agent_enabled
  user_account   = local.vm_user_account
}

module "master" {
  source = "./modules/vm"
  count  = length(var.masters)

  name           = var.masters[count.index].name
  vm_id          = var.masters[count.index].vm_id
  node_name      = coalesce(var.masters[count.index].node, var.proxmox_node)
  description    = "RKE2 server ${var.rke2_version} (managed by Terraform)"
  tags           = ["terraform", "k8s", "rke2-master"]
  cores          = var.master_resources.cores
  memory_mb      = var.master_resources.memory_mb
  disk_gb        = var.master_resources.disk_gb
  cpu_type       = var.cpu_type
  bios           = var.bios
  scsi_hardware  = var.scsi_hardware
  network_model  = var.network_model
  datastore_id   = var.vm_datastore
  template_id    = var.template_id
  template_node  = local.template_node
  disk_interface = var.template_disk_interface
  bridge         = var.network_bridge
  vlan_id        = var.vlan_id
  ip_cidr        = var.masters[count.index].ip
  gateway        = var.gateway
  dns_servers    = var.dns_servers
  dns_domain     = var.dns_domain
  agent_enabled  = var.agent_enabled
  user_account   = local.vm_user_account
}

module "worker" {
  source = "./modules/vm"
  count  = length(var.workers)

  name           = var.workers[count.index].name
  vm_id          = var.workers[count.index].vm_id
  node_name      = coalesce(var.workers[count.index].node, var.proxmox_node)
  description    = "RKE2 agent ${var.rke2_version} (managed by Terraform)"
  tags           = ["terraform", "k8s", "rke2-worker"]
  cores          = var.worker_resources.cores
  memory_mb      = var.worker_resources.memory_mb
  disk_gb        = var.worker_resources.disk_gb
  cpu_type       = var.cpu_type
  bios           = var.bios
  scsi_hardware  = var.scsi_hardware
  network_model  = var.network_model
  datastore_id   = var.vm_datastore
  template_id    = var.template_id
  template_node  = local.template_node
  disk_interface = var.template_disk_interface
  bridge         = var.network_bridge
  vlan_id        = var.vlan_id
  ip_cidr        = var.workers[count.index].ip
  gateway        = var.gateway
  dns_servers    = var.dns_servers
  dns_domain     = var.dns_domain
  agent_enabled  = var.agent_enabled
  user_account   = local.vm_user_account
}
