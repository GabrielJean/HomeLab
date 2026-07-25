
variable "pve1_api_url" {
  description = "Proxmox API URL for node 1"
  type        = string
}

variable "pve1_username" {
  description = "Proxmox username for node 1 (e.g. root@pam)"
  type        = string
}

variable "pve1_password" {
  description = "Proxmox password for node 1"
  type        = string
  sensitive   = true
}

variable "pve2_api_url" {
  description = "Proxmox API URL for node 2"
  type        = string
}

variable "pve2_username" {
  description = "Proxmox username for node 2 (e.g. root@pam)"
  type        = string
}

variable "pve2_password" {
  description = "Proxmox password for node 2"
  type        = string
  sensitive   = true
}
