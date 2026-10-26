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
  description = "Node the new VM is created on"
  type        = string
  default     = "hvir111d"
}

variable "template_id" {
  description = "Template to clone"
  type        = number
  default     = 104
}

variable "template_node" {
  description = "Node holding the template; empty = node_name"
  type        = string
  default     = ""
}

variable "datastore" {
  description = "Datastore for the cloned disks; empty = same as the template"
  type        = string
  default     = "iscsi-netapp"
}

variable "vm_id" {
  description = "ID of the new VM; null = next free ID"
  type        = number
  default     = 400
}

variable "vm_name" {
  type    = string
  default = "clone-test"
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "network_devices" {
  description = "Network cards by slot (net0, net1, ...). Slots not listed keep the template's settings."
  type = map(object({
    bridge      = string
    model       = optional(string) # virtio, vmxnet3, e1000
    vlan_id     = optional(number)
    mac_address = optional(string) # omitted = new random MAC
    firewall    = optional(bool)
    mtu         = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.network_devices) : can(regex("^net[0-9]+$", k))])
    error_message = "network_devices keys must be slot names like net0, net1."
  }
}

variable "ip_configs" {
  description = "Cloud-init IP per slot (net0 -> ipconfig0). address = 'dhcp' or CIDR like 192.168.1.80/24. Empty = template's."
  type = map(object({
    address = string
    gateway = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.ip_configs) : can(regex("^net[0-9]+$", k))])
    error_message = "ip_configs keys must be slot names like net0, net1."
  }

  validation {
    condition     = alltrue([for c in values(var.ip_configs) : c.address == "dhcp" || can(cidrhost(c.address, 0))])
    error_message = "address must be 'dhcp' or an IP with prefix, e.g. 192.168.1.80/24."
  }
}

variable "dns_servers" {
  description = "Cloud-init DNS servers; empty = template's"
  type        = list(string)
  default     = []
}

variable "dns_domain" {
  description = "Cloud-init search domain; empty = template's"
  type        = string
  default     = ""
}
