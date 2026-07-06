# =============================================================================
# modules/networking/main.tf
# Crea: VNet, Subnets, NSGs, Route Tables y diagnósticos
# =============================================================================

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space

  # Azure DNS privado (recomendado para resolución interna)
  dns_servers = []

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Subnet: Nodos AKS
# Delegada para que AKS gestione las interfaces de red
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_cidr]

  # Requerido para Cilium con Azure CNI Overlay
  private_endpoint_network_policies             = "Disabled"
  private_link_service_network_policies_enabled = false
}

# -----------------------------------------------------------------------------
# Subnet: Application Gateway (AGIC / NGINX con IP pública)
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

# -----------------------------------------------------------------------------
# Subnet: Private Endpoints (bases de datos, Key Vault, ACR, etc.)
# -----------------------------------------------------------------------------
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe-${var.environment}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoint_subnet_cidr]

  private_endpoint_network_policies             = "Disabled"
}

# =============================================================================
# Network Security Groups
# =============================================================================

# NSG para nodos AKS
resource "azurerm_network_security_group" "aks_nodes" {
  name                = "nsg-aks-nodes-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Regla: permitir tráfico interno del VNet
  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Regla: permitir Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowInternetInboundHTTP"
    priority                   = 115
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowInternetInboundNodePorts"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "30000-32767"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Regla: bloquear todo el tráfico externo no autorizado
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "aks_nodes" {
  subnet_id                 = azurerm_subnet.aks_nodes.id
  network_security_group_id = azurerm_network_security_group.aks_nodes.id
}

# NSG para Application Gateway
resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-appgw-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  # Requerido por Azure para gestión del Application Gateway
  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

# =============================================================================
# Diagnósticos de VNet (Log Analytics)
# Azure Policy suele requerir esto en entornos enterprise
# =============================================================================
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}
