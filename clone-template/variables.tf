variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://10.0.0.11:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token as '<user>@<realm>!<token-id>=<secret>'"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (self-signed Proxmox certificate)"
  type        = bool
  default     = true
}

variable "node_name" {
  description = "Default node for the new VMs (each VM can override it with 'node')"
  type        = string
  default     = "hvir111d"
}

variable "template_id" {
  description = "Template to clone"
  type        = number
  default     = 104
}

variable "template_node" {
  description = "Node holding the template; empty = node_name. VMs on other nodes are cloned from there (the template's disks must be on shared storage)."
  type        = string
  default     = ""
}

variable "datastore" {
  description = "Datastore for the cloned disks; empty = same as the template"
  type        = string
  default     = "iscsi-netapp"
}

variable "disk_interface" {
  description = "The template's boot disk slot (template > Hardware)"
  type        = string
  default     = "scsi0"
}

variable "template_disk_gb" {
  description = "Size of the template's disk; a clone's disk can't be smaller"
  type        = number
  default     = 50
}

variable "disk_gb" {
  description = "Default disk size of the VMs in GB (a VM can override it)"
  type        = number
  default     = 50
}

variable "start_vms" {
  description = "Start the VMs once they are configured"
  type        = bool
  default     = true
}

variable "dns_servers" {
  description = "Cloud-init DNS servers for all VMs (a VM can override them); empty = template's"
  type        = list(string)
  default     = []
}

variable "dns_domain" {
  description = "Cloud-init search domain for all VMs (a VM can override it); empty = template's"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Network defaults, used by every VM unless the VM sets its own value
# ---------------------------------------------------------------------------
variable "network_bridge" {
  type    = string
  default = "vmbr1"
}

variable "network_model" {
  description = "virtio, vmxnet3 or e1000"
  type        = string
  default     = "vmxnet3"
}

variable "vlan_id" {
  description = "VLAN tag (null = untagged)"
  type        = number
  default     = null
}

variable "gateway" {
  description = "Default gateway (empty = none)"
  type        = string
  default     = ""
}

variable "ip_prefix" {
  description = "Prefix length added to IPs written without one (24 = 255.255.255.0)"
  type        = number
  default     = 24
}

# ---------------------------------------------------------------------------
# VMs
# ---------------------------------------------------------------------------
variable "vms" {
  description = <<-EOT
    VMs to create, one entry per VM. 'ip' is for the first network card (net0):
    a plain IP (ip_prefix is added), IP/prefix, or "dhcp"; omitted = template's.
    Every other field is optional and falls back to the global value.
  EOT
  type = list(object({
    name    = string
    vm_id   = number
    ip      = optional(string)
    disk_gb = optional(number)
    node    = optional(string)

    # First network card (net0); defaults from the global variables.
    bridge      = optional(string)
    model       = optional(string)
    vlan_id     = optional(number)
    gateway     = optional(string)
    mac_address = optional(string) # omitted = new random MAC
    firewall    = optional(bool)
    mtu         = optional(number)

    # Extra network cards by slot (net1, net2, ...).
    extra_networks = optional(map(object({
      bridge      = optional(string)
      model       = optional(string)
      vlan_id     = optional(number)
      mac_address = optional(string)
      firewall    = optional(bool)
      mtu         = optional(number)
      ip          = optional(string)
      gateway     = optional(string) # usually only net0 has a gateway
    })), {})

    dns_servers = optional(list(string))
    dns_domain  = optional(string)
  }))

  validation {
    condition     = length(distinct([for vm in var.vms : vm.name])) == length(var.vms)
    error_message = "Every VM needs its own name."
  }

  validation {
    condition     = length(distinct([for vm in var.vms : vm.vm_id])) == length(var.vms)
    error_message = "Every VM needs its own vm_id."
  }

  validation {
    condition     = alltrue([for vm in var.vms : coalesce(vm.disk_gb, var.disk_gb) >= var.template_disk_gb])
    error_message = "disk_gb can't be smaller than the template's disk (template_disk_gb)."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [for slot in keys(vm.extra_networks) : can(regex("^net[1-9][0-9]*$", slot))]
    ]))
    error_message = "extra_networks keys must be slot names like net1, net2."
  }

  validation {
    condition = alltrue(flatten([
      for vm in var.vms : [
        for ip in concat([vm.ip], [for n in values(vm.extra_networks) : n.ip]) :
        ip == null || ip == "dhcp" || can(cidrhost(strcontains(coalesce(ip, "x"), "/") ? ip : "${ip}/32", 0))
      ]
    ]))
    error_message = "ip must be 'dhcp', an IP (192.168.1.61) or IP/prefix (192.168.1.61/24)."
  }
}
