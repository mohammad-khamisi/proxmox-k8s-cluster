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
