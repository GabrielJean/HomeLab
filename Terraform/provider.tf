terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.96.0"
    }
  }
}




provider "proxmox" {
  endpoint = var.pve1_api_url
  username = var.pve1_username
  password = var.pve1_password
}

provider "proxmox" {
  alias    = "pve1"
  endpoint = var.pve1_api_url
  username = var.pve1_username
  password = var.pve1_password
}



provider "proxmox" {
  alias    = "pve2"
  endpoint = var.pve2_api_url
  username = var.pve2_username
  password = var.pve2_password
}
