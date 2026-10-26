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
  description = "Node holding the template; empty = the VM's node"
  type        = string
  default     = ""
}

variable "datastore" {
  description = "Datastore for the cloned disks; empty = same as the template"
  type        = string
  default     = "iscsi-netapp"
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

variable "vms" {
  description = <<-EOT
    VMs to create, keyed by VM name. 'networks' is keyed by slot (net0, net1, ...):
    network card settings plus an optional cloud-init IP ('dhcp' or IP/prefix).
    Slots not listed keep the template's settings.
  EOT
  type = map(object({
    vm_id = number
    node  = optional(string)
    networks = optional(map(object({
      bridge      = string
      model       = optional(string) # virtio, vmxnet3, e1000
      vlan_id     = optional(number)
      mac_address = optional(string) # omitted = new random MAC
      firewall    = optional(bool)
      mtu         = optional(number)
      ip          = optional(string) # "dhcp" or "192.168.1.61/24"; omitted = template's
      gateway     = optional(string)
    })), {})
    dns_servers = optional(list(string))
    dns_domain  = optional(string)
  }))

  validation {
    condition     = length(distinct([for vm in values(var.vms) : vm.vm_id])) == length(var.vms)
    error_message = "Every VM needs its own vm_id."
  }

  validation {
    condition = alltrue(flatten([
      for vm in values(var.vms) : [for slot in keys(vm.networks) : can(regex("^net[0-9]+$", slot))]
    ]))
    error_message = "networks keys must be slot names like net0, net1."
  }

  validation {
    condition = alltrue(flatten([
      for vm in values(var.vms) : [
        for n in values(vm.networks) : n.ip == null || n.ip == "dhcp" || can(cidrhost(n.ip, 0))
      ]
    ]))
    error_message = "ip must be 'dhcp' or an IP with prefix, e.g. 192.168.1.61/24."
  }
}
