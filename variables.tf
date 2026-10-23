# ---------------------------------------------------------------------------
# Proxmox
# ---------------------------------------------------------------------------
variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://10.0.0.11:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token as '<user>@<realm>!<token-id>=<secret>'"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@!=\\s]+@[^@!=\\s]+![^@!=\\s]+=[^\\s]+$", var.proxmox_api_token))
    error_message = "proxmox_api_token must look like 'terraform@pve!provider=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed Proxmox certificate)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Default node for the VMs (each VM can override it with 'node')"
  type        = string
  default     = "hvir111d"
}

# ---------------------------------------------------------------------------
# Template and VM hardware
# ---------------------------------------------------------------------------
variable "template_id" {
  description = "Cloud-init template to full-clone (8000 = template-rocky-10-proxmox)"
  type        = number
  default     = 8000
}

variable "template_node" {
  description = "Node holding the template; empty = proxmox_node. VMs on other nodes need the template on shared storage."
  type        = string
  default     = ""
}

variable "template_disk_interface" {
  description = "Interface of the template's boot disk (template > Hardware), e.g. scsi0 or virtio0"
  type        = string
  default     = "scsi0"
}

variable "vm_datastore" {
  description = "Datastore for the cloned disks and the cloud-init drive"
  type        = string
  default     = "iscsi-netapp"
}

variable "cpu_type" {
  description = "Rocky Linux 10 needs x86-64-v3: use 'host' or 'x86-64-v3' (not the kvm64/x86-64-v2 defaults)"
  type        = string
  default     = "host"
}

variable "agent_enabled" {
  description = "true only if the template already has qemu-guest-agent installed (Terraform waits for it)"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the VMs (null = untagged)"
  type        = number
  default     = null
}

variable "gateway" {
  description = "Default gateway (IP only, without prefix)"
  type        = string

  validation {
    condition     = can(cidrhost("${var.gateway}/32", 0))
    error_message = "gateway must be a plain IPv4 address, e.g. 192.168.1.1."
  }
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "dns_domain" {
  description = "Search domain (optional)"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------
variable "vm_user" {
  description = "User created by cloud-init on every VM"
  type        = string
  default     = "rocky"
}

variable "ssh_public_keys" {
  description = "Your public key(s), allowed on every VM"
  type        = list(string)
}

variable "ssh_private_key_path" {
  description = "Private key matching ssh_public_keys (no passphrase); Terraform uses it to provision the VMs"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "provision_via_jumpbox" {
  description = "true = Terraform reaches the cluster nodes through the jumpbox (SSH bastion); false = directly"
  type        = bool
  default     = false
}

variable "timezone" {
  type    = string
  default = "UTC"
}

# ---------------------------------------------------------------------------
# VMs
# ---------------------------------------------------------------------------
variable "masters" {
  description = "Control-plane nodes (odd number, 3 for HA etcd). The first one bootstraps the cluster."
  type = list(object({
    name  = string
    vm_id = number
    ip    = string # CIDR, e.g. 192.168.1.61/24
    node  = optional(string)
  }))

  validation {
    condition     = length(var.masters) % 2 == 1
    error_message = "Use an odd number of masters (1, 3, 5) so etcd keeps quorum."
  }
}

variable "workers" {
  description = "Worker nodes"
  type = list(object({
    name  = string
    vm_id = number
    ip    = string
    node  = optional(string)
  }))
}

variable "jumpbox" {
  description = "Jumpbox VM: kubectl, helm and the kubeconfig; SSH access to every node"
  type = object({
    name  = string
    vm_id = number
    ip    = string
    node  = optional(string)
  })
}

variable "master_resources" {
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = { cores = 4, memory_mb = 8192, disk_gb = 60 }
}

variable "worker_resources" {
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = { cores = 4, memory_mb = 8192, disk_gb = 80 }
}

variable "jumpbox_resources" {
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = { cores = 2, memory_mb = 2048, disk_gb = 30 }
}

# ---------------------------------------------------------------------------
# RKE2
# ---------------------------------------------------------------------------
variable "rke2_version" {
  type    = string
  default = "v1.36.5+rke2r1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "rke2_version must look like v1.36.5+rke2r1."
  }
}

variable "rke2_install_method" {
  description = "'tar' (works on any distro) or 'rpm' (needs rke2 RPMs for your EL version)"
  type        = string
  default     = "tar"

  validation {
    condition     = contains(["tar", "rpm"], var.rke2_install_method)
    error_message = "rke2_install_method must be 'tar' or 'rpm'."
  }
}

variable "rke2_cni" {
  description = "canal, calico, cilium or flannel"
  type        = string
  default     = "canal"
}

variable "api_endpoint" {
  description = "Optional DNS name or VIP in front of the masters (added to the certificate and used in the kubeconfig). Empty = first master's IP."
  type        = string
  default     = ""
}

variable "taint_masters" {
  description = "Keep workloads off the masters (CriticalAddonsOnly taint)"
  type        = bool
  default     = true
}

variable "selinux_permissive" {
  description = "Set SELinux to permissive on the nodes (the tar install has no rke2-selinux policy)"
  type        = bool
  default     = true
}

variable "helm_version" {
  type    = string
  default = "v3.19.0"
}
