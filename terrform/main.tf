locals {
  location = "southeastasia"
  name     = "gaia"
}

resource "random_id" "prefix" {
  byte_length = 6
}

resource "azurerm_resource_group" "this" {
  location = local.location 
  name     = "${local.name}-${random_id.prefix.hex}-rg" 
}

resource "azurerm_virtual_network" "this" {
  address_space       = ["10.52.0.0/16"]
  location            = local.location
  name                = "${local.name}-${random_id.prefix.hex}-vnet"
  resource_group_name = azurerm_resource_group.this.name 
}

resource "azurerm_subnet" "aks" {
  address_prefixes     = ["10.52.0.0/24"]
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.this.name 
  virtual_network_name = azurerm_virtual_network.this.name 
}

resource "azurerm_subnet" "pg" {
  address_prefixes     = ["10.52.1.0/24"]
  name                 = "pg-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  delegation {
    name = "pg-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      # actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_container_registry" "this" {
  location            = local.location 
  name                = "${local.name}${random_id.prefix.hex}acr" 
  resource_group_name = azurerm_resource_group.this.name 
  sku                 = "Basic"
}

module "aks" {
  source = "Azure/aks/azurerm"

  prefix                    = "${local.name}-${random_id.prefix.hex}"
  resource_group_name       = azurerm_resource_group.this.name 
  location                  = local.location 
  kubernetes_version        = "1.32" # don't specify the patch version!
  automatic_channel_upgrade = "patch"
  agents_count = 1
  attached_acr_id_map = {
    ecr = azurerm_container_registry.this.id 
  }
  network_plugin  = "azure"
  network_policy  = "azure"
  os_disk_size_gb = 60
  rbac_aad        = false
  sku_tier        = "Free" 
  vnet_subnet = {
    id = azurerm_subnet.aks.id 
  }
}


resource "azurerm_private_dns_zone" "this" {
  name                = "privatelink.postgres.database.azure.com" 
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "pg-subnet-link" 
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = azurerm_virtual_network.this.id
  resource_group_name   = azurerm_resource_group.this.name
  depends_on            = [azurerm_subnet.pg]
}

resource "random_password" "pg" {
  length  = 8 
  special = true
  upper   = true
  lower   = true
  number  = true 
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "${local.name}-${random_id.prefix.hex}-pg" 
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  version                       = "16"
  delegated_subnet_id           = azurerm_subnet.pg.id
  private_dns_zone_id           = azurerm_private_dns_zone.this.id
  public_network_access_enabled = false
  administrator_login           = "psqladmin"
  administrator_password        = random_password.pg.result
  zone                          = "1"

  storage_mb   = 32768
  storage_tier = "P4"

  sku_name   = "B_Standard_B1ms"
  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}