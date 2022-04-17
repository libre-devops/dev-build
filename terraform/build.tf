module "rg" {
  source = "registry.terraform.io/libre-devops/rg/azurerm"

  rg_name    = "rg-${var.short}-${var.loc}-${terraform.workspace}-build"
  location   = local.location
  lock_level = "CanNotDelete"
  tags       = local.tags
}

module "network" {
  source = "registry.terraform.io/libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location

  vnet_name     = "vnet-${var.short}-${var.loc}-${terraform.workspace}-01"
  vnet_location = module.network.vnet_location

  address_space   = ["10.0.0.0/16"]
  subnet_prefixes = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  subnet_names    = ["sn1-${module.network.vnet_name}", "sn2-${module.network.vnet_name}", "sn3-${module.network.vnet_name}"]

  subnet_service_endpoints = {
    subnet2 = ["Microsoft.Storage", "Microsoft.Sql"],
    subnet3 = ["Microsoft.AzureActiveDirectory"]
  }

  tags = local.tags
}

module "nsg" {
  source = "../../terraform-azurerm-nsg"

  rg_name   = module.rg.rg_name
  location  = module.rg.rg_location
  nsg_name  = "nsg-${var.short}-${var.loc}-${terraform.workspace}"
  subnet_id = element(module.network.subnets_ids, 0)

  tags = module.rg.rg_tags
}

resource "azurerm_network_interface" "nic" {
  count = module.win_vm.vm_amount

  name                = "${module.win_vm.vm_name}${format("%02d", count.index + 1)}-nic"
  resource_group_name = module.rg.rg_name
  location            = module.rg.rg_location

  enable_accelerated_networking = false

  ip_configuration {
    name                          = "${module.win_vm.vm_name}${format("%02d", count.index + 1)}-ipconfig"
    primary                       = true
    private_ip_address_allocation = "dynamic"
    subnet_id                     = element(module.network.subnets_ids, 0)
  }
  tags = module.rg.rg_tags

  timeouts {
    create = "5m"
    delete = "10m"
  }
}

module "win_vm" {
  source = "../../terraform-azurerm-windows-vm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location

  vm_amount          = 2
  vm_hostname        = "vm${var.short}${var.loc}${terraform.workspace}${format("%02d", count.index + 1)}"
  vm_size            = "Standard_B2ms"
  vm_os_simple       = "WindowsServer2019"
  vm_os_disk_size_gb = "127"

  admin_username = "LibreDevOpsAdmin"
  admin_password = data.azurerm_key_vault_secret.mgmt_local_admin_pwd.value

  nic_ids = [
    azurerm_network_interface.nic[count.index].id
  ]

  availability_zone    = "alternate"
  storage_account_type = "Standard_LRS"
  identity_type        = "SystemAssigned"

  tags = module.rg.rg_tags
}