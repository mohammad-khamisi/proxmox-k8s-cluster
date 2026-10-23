# Uploads the setup scripts to a VM over SSH and runs them with sudo.
locals {
  dir = "/tmp/rke2-setup"
}

resource "terraform_data" "this" {
  # Run again only when the VM is replaced.
  triggers_replace = [var.vm_id]

  connection {
    type        = "ssh"
    host        = var.host
    user        = var.user
    private_key = file(pathexpand(var.private_key_path))
    timeout     = "10m"

    bastion_host        = var.bastion_host
    bastion_user        = var.bastion_host == null ? null : var.user
    bastion_private_key = var.bastion_host == null ? null : file(pathexpand(var.private_key_path))
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p ${local.dir} && chmod 700 ${local.dir}"]
  }

  provisioner "file" {
    content     = var.prepare_script
    destination = "${local.dir}/prepare-node.sh"
  }

  provisioner "file" {
    content     = var.hosts
    destination = "${local.dir}/hosts"
  }

  provisioner "file" {
    content     = var.role_script
    destination = "${local.dir}/role.sh"
  }

  provisioner "file" {
    content     = var.role_config == "" ? "# unused\n" : var.role_config
    destination = "${local.dir}/config.yaml"
  }

  provisioner "file" {
    content     = var.extra_file == "" ? "# unused\n" : var.extra_file
    destination = "${local.dir}/extra"
  }

  # Output is streamed here and logged to /var/log/rke2-setup.log on the VM.
  provisioner "remote-exec" {
    inline = [
      "set -o pipefail; sudo bash -c 'bash ${local.dir}/prepare-node.sh ${var.prepare_args} && bash ${local.dir}/role.sh ${var.role_args}' 2>&1 | sudo tee -a /var/log/rke2-setup.log",
      "sudo rm -rf ${local.dir}",
    ]
  }
}
