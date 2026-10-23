variable "name" { type = string }
variable "vm_id" { type = number }
variable "node_name" { type = string }
variable "description" {
  type    = string
  default = ""
}
variable "tags" {
  type    = list(string)
  default = []
}
variable "cores" { type = number }
variable "memory_mb" { type = number }
variable "disk_gb" { type = number }
variable "cpu_type" {
  description = "Rocky/RHEL 10 needs x86-64-v3 or newer ('host' or 'x86-64-v3')"
  type        = string
  default     = "host"
}
variable "datastore_id" { type = string }
variable "template_id" {
  description = "Template VM ID to full-clone"
  type        = number
}
variable "template_node" {
  description = "Node holding the template (null = same node)"
  type        = string
  default     = null
}
variable "disk_interface" {
  description = "Interface of the template's boot disk (see the template's Hardware tab)"
  type        = string
  default     = "scsi0"
}
variable "bridge" { type = string }
variable "vlan_id" {
  type    = number
  default = null
}
variable "ip_cidr" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }
variable "dns_domain" {
  type    = string
  default = null
}
variable "agent_enabled" {
  description = "Wait for the QEMU guest agent (only if the template already has it)"
  type        = bool
  default     = false
}
variable "user_account" {
  description = "Proxmox built-in cloud-init user"
  type = object({
    username = string
    keys     = list(string)
    password = string
  })
  sensitive = true
}
