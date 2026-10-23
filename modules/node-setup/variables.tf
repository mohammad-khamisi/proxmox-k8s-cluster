variable "vm_id" { type = number }
variable "host" { type = string }
variable "user" { type = string }
variable "private_key_path" { type = string }
variable "bastion_host" {
  description = "SSH bastion (the jumpbox) or null for a direct connection"
  type        = string
  default     = null
}
variable "prepare_script" { type = string }
variable "prepare_args" { type = string }
variable "hosts" {
  description = "Lines appended to /etc/hosts"
  type        = string
}
variable "role_script" { type = string }
variable "role_args" { type = string }
variable "role_config" {
  description = "RKE2 config.yaml (empty for the jumpbox)"
  type        = string
  default     = ""
  sensitive   = true
}
variable "extra_file" {
  description = "Extra file passed to the role script (the jumpbox's SSH private key)"
  type        = string
  default     = ""
  sensitive   = true
}
