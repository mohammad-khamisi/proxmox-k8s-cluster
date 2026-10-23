# ---------------------------------------------------------------------------
# Node setup over SSH: OS preparation, then RKE2 server/agent or jumpbox tools.
# Order: first master (bootstraps etcd) -> other masters + workers -> jumpbox.
# ---------------------------------------------------------------------------
locals {
  # Strip CR so files checked out with Windows line endings still run on Linux.
  scripts = {
    for name in ["prepare-node.sh", "install-rke2.sh", "setup-jumpbox.sh"] :
    name => replace(file("${path.module}/scripts/${name}"), "\r", "")
  }

  hosts_file   = join("", [for name, ip in local.hosts : "${ip} ${name}\n"])
  prepare_args = "${var.timezone} ${var.selinux_permissive}"
  rke2_args    = "${var.rke2_version} ${var.rke2_install_method}"
  bastion_host = var.provision_via_jumpbox ? local.jumpbox_ip : null

  server_config = {
    token                   = random_password.rke2_token.result
    tls-san                 = local.tls_san
    write-kubeconfig-mode   = "0600"
    cni                     = var.rke2_cni
    node-taint              = var.taint_masters ? ["CriticalAddonsOnly=true:NoExecute"] : []
    etcd-snapshot-retention = 10
  }

  first_master_config = yamlencode(merge(local.server_config, {
    node-name = var.masters[0].name
    node-ip   = local.master_ips[0]
  }))

  join_master_configs = [
    for i, m in var.masters : yamlencode(merge(local.server_config, {
      server    = "https://${local.first_master_ip}:9345"
      node-name = m.name
      node-ip   = local.master_ips[i]
    }))
  ]

  worker_configs = [
    for i, w in var.workers : yamlencode({
      server    = "https://${local.first_master_ip}:9345"
      token     = random_password.rke2_token.result
      node-name = w.name
      node-ip   = local.worker_ips[i]
    })
  ]
}

module "setup_first_master" {
  source = "./modules/node-setup"

  vm_id            = module.master[0].vm_id
  host             = module.master[0].ip
  user             = var.vm_user
  private_key_path = var.ssh_private_key_path
  bastion_host     = local.bastion_host
  prepare_script   = local.scripts["prepare-node.sh"]
  prepare_args     = local.prepare_args
  hosts            = local.hosts_file
  role_script      = local.scripts["install-rke2.sh"]
  role_args        = "server ${local.rke2_args}"
  role_config      = local.first_master_config

  depends_on = [module.jumpbox]
}

module "setup_master" {
  source = "./modules/node-setup"
  count  = length(var.masters) - 1

  vm_id            = module.master[count.index + 1].vm_id
  host             = module.master[count.index + 1].ip
  user             = var.vm_user
  private_key_path = var.ssh_private_key_path
  bastion_host     = local.bastion_host
  prepare_script   = local.scripts["prepare-node.sh"]
  prepare_args     = local.prepare_args
  hosts            = local.hosts_file
  role_script      = local.scripts["install-rke2.sh"]
  role_args        = "server ${local.rke2_args}"
  role_config      = local.join_master_configs[count.index + 1]

  depends_on = [module.setup_first_master]
}

module "setup_worker" {
  source = "./modules/node-setup"
  count  = length(var.workers)

  vm_id            = module.worker[count.index].vm_id
  host             = module.worker[count.index].ip
  user             = var.vm_user
  private_key_path = var.ssh_private_key_path
  bastion_host     = local.bastion_host
  prepare_script   = local.scripts["prepare-node.sh"]
  prepare_args     = local.prepare_args
  hosts            = local.hosts_file
  role_script      = local.scripts["install-rke2.sh"]
  role_args        = "agent ${local.rke2_args}"
  role_config      = local.worker_configs[count.index]

  depends_on = [module.setup_first_master]
}

# kubectl, helm, SSH key to the nodes and the kubeconfig (copied from the
# first master, pointing at api_endpoint).
module "setup_jumpbox" {
  source = "./modules/node-setup"

  vm_id            = module.jumpbox.vm_id
  host             = module.jumpbox.ip
  user             = var.vm_user
  private_key_path = var.ssh_private_key_path
  prepare_script   = local.scripts["prepare-node.sh"]
  prepare_args     = local.prepare_args
  hosts            = local.hosts_file
  role_script      = local.scripts["setup-jumpbox.sh"]
  role_args        = "${var.vm_user} ${local.kubectl_version} ${var.helm_version} ${local.first_master_ip} ${local.api_endpoint}"
  extra_file       = tls_private_key.jumpbox.private_key_openssh

  depends_on = [module.setup_master, module.setup_worker]
}
