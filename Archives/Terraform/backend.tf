terraform {
  backend "azurerm" {
    resource_group_name  = "GJ-HomeLab-RG"
    storage_account_name = "gjterraformstatesa"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}