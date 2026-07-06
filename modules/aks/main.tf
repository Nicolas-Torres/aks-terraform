# =============================================================================
# modules/aks/main.tf
# Crea: Cluster AKS con Cilium, 3 AZs, AGIC y add-ons enterprise
# =============================================================================

# -----------------------------------------------------------------------------
# IP Pública para el Ingress (Application Gateway o NGINX)
# Se usa dominio público mediante esta IP estática
# -----------------------------------------------------------------------------
# resource "azurerm_public_ip" "appgw" {
#   name                = "pip-appgw-${var.project}-${var.environment}"
#   resource_group_name = var.resource_group_name
#   location            = var.location
#   allocation_method   = "Static"
#   sku                 = "Standard"         # Standard requerido para zonas y AGIC
#   zones               = var.availability_zones

#   # El FQDN de esta IP puede usarse como registro DNS tipo A o CNAME
#   domain_name_label = "${var.project}-${var.environment}-ingress"

#   tags = var.tags
# }

# resource "azurerm_web_application_firewall_policy" "agw_waf" {
#   name                = "waf-${var.project}-${var.environment}-${var.location_short}"
#   resource_group_name = var.resource_group_name
#   location            = var.location

#   managed_rules {
#     managed_rule_set {
#       type    = "OWASP"
#       version = "3.2"
#     }
#   }
# }

# -----------------------------------------------------------------------------
# Application Gateway v2 (Ingress para dominio público)
# Compatible con AGIC (Application Gateway Ingress Controller)
# -----------------------------------------------------------------------------
# resource "azurerm_application_gateway" "main" {
#   name                = "agw-${var.project}-${var.environment}-${var.location_short}"
#   resource_group_name = var.resource_group_name
#   location            = var.location
#   zones               = var.availability_zones   # HA en 3 zonas
#   # firewall_policy_id  = azurerm_web_application_firewall_policy.agw_waf.id

#   sku {
#     name = "Standard_v2" #"WAF_v2"    # WAF incluido para protección de capa 7
#     tier = "Standard_v2" #"WAF_v2"     # Mínimo recomendado; el autoscale se configura abajo
#   }

#   # Autoscaling del Application Gateway
#   autoscale_configuration {
#     min_capacity = 2
#     max_capacity = 4
#   }

#   ssl_policy {
#     policy_type = "Predefined"
#     policy_name = "AppGwSslPolicy20170401S"
#   }

#   gateway_ip_configuration {
#     name      = "appgw-ip-config"
#     subnet_id = var.appgw_subnet_id
#   }

#   # Frontend IP pública
#   frontend_ip_configuration {
#     name                 = "appgw-frontend-public"
#     public_ip_address_id = azurerm_public_ip.appgw.id
#   }

#   # Puerto HTTP (AGIC crea los listeners dinámicamente, estos son los base)
#   frontend_port {
#     name = "port-80"
#     port = 80
#   }

#   frontend_port {
#     name = "port-443"
#     port = 443
#   }

#   # Backend pool vacío - AGIC lo gestiona dinámicamente
#   backend_address_pool {
#     name = "appgw-backend-pool"
#   }

#   backend_http_settings {
#     name                  = "appgw-backend-http"
#     cookie_based_affinity = "Disabled"
#     port                  = 80
#     protocol              = "Http"
#     request_timeout       = 60
#   }

#   http_listener {
#     name                           = "appgw-listener-http"
#     frontend_ip_configuration_name = "appgw-frontend-public"
#     frontend_port_name             = "port-80"
#     protocol                       = "Http"
#   }

#   request_routing_rule {
#     name                       = "appgw-routing-rule"
#     rule_type                  = "Basic"
#     priority                   = 100
#     http_listener_name         = "appgw-listener-http"
#     backend_address_pool_name  = "appgw-backend-pool"
#     backend_http_settings_name = "appgw-backend-http"
#   }

#   # Identidad gestionada para que AGIC lea secrets (TLS desde Key Vault)
#   #identity {
#   #  type         = "SystemAssigned" # "UserAssigned"
#     #identity_ids = [azurerm_user_assigned_identity.agic.id]
#   #}

#   tags = var.tags

#   lifecycle {
#     # AGIC modifica el Application Gateway; ignorar cambios para evitar drift
#     ignore_changes = [
#       backend_address_pool,
#       backend_http_settings,
#       frontend_port,
#       http_listener,
#       probe,
#       redirect_configuration,
#       request_routing_rule,
#       ssl_certificate,
#       tags["managed-by-k8s-ingress"],
#     ]
#   }
# }

# -----------------------------------------------------------------------------
# Identidad de AGIC
# -----------------------------------------------------------------------------
# El addon ingress_application_gateway crea automáticamente su propia identidad
# administrada (ingressapplicationgateway-<cluster>). Esa identidad necesita
# Contributor sobre el Application Gateway y Reader sobre su Resource Group;
# AKS no asigna estos roles por sí mismo, hay que crearlos explícitamente.

# resource "azurerm_role_assignment" "agic_appgw_contributor" {
#   scope                = azurerm_application_gateway.main.id
#   role_definition_name = "Contributor"
#   principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
# }

# resource "azurerm_role_assignment" "agic_rg_reader" {
#   scope                = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}"
#   role_definition_name = "Reader"
#   principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
# }

# # Network Contributor sobre la subnet del Application Gateway: requerido para
# # el permiso "Microsoft.Network/virtualNetworks/subnets/join/action" que Azure
# # exige en cada CreateOrUpdate del AGW. Sin este rol, AGIC falla con
# # "ApplicationGatewayInsufficientPermissionOnSubnet" al sincronizar el Ingress.
# resource "azurerm_role_assignment" "agic_appgw_subnet_join" {
#   scope                = var.appgw_subnet_id
#   role_definition_name = "Network Contributor"
#   principal_id         = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
# }

# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------
data "azurerm_subscription" "current" {}

# -----------------------------------------------------------------------------
# Cluster AKS
# =============================================================================
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kubernetes_version  = var.kubernetes_version
  dns_prefix          = coalesce(var.dns_prefix, "${var.project}-${var.environment}")

  # ⚠️ Buenas prácticas: node resource group con nombre explícito
  node_resource_group = "rg-${var.project}-${var.environment}-aks-nodes"

  # Cluster privado (recomendado para producción)
  private_cluster_enabled             = var.private_cluster_enabled
  private_cluster_public_fqdn_enabled = !var.private_cluster_enabled

  # Actualizaciones automáticas de parches de seguridad del canal "patch"
  automatic_channel_upgrade = "patch"

  # Mantenimiento programado (fines de semana, menor impacto)
  maintenance_window {
    allowed {
      day   = "Saturday"
      hours = [2, 3]
    }
    allowed {
      day   = "Sunday"
      hours = [2, 3]
    }
  }

  # ===========================================================================
  # System Node Pool - Solo cargas de sistema (cordon + taint automático)
  # ===========================================================================
  default_node_pool {
    name                         = var.system_node_pool.name
    vm_size                      = var.system_node_pool.vm_size
    zones                        = var.availability_zones      # ← 3 AZs
    enable_auto_scaling         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    os_disk_type                 = var.system_node_pool.os_disk_type
    max_pods                     = var.system_node_pool.max_pods
    vnet_subnet_id               = var.aks_subnet_id
    only_critical_addons_enabled = true  # Solo pods de sistema en este pool
    temporary_name_for_rotation  = "systemtemp"  # Requerido para rotaciones sin downtime

    # Seguridad: host-based encryption
    enable_host_encryption = false  # Requiere feature flag habilitado en suscripción

    upgrade_settings {
      max_surge                     = "1"
      drain_timeout_in_minutes      = 30
      node_soak_duration_in_minutes = 0
    }

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
    }
  }

  # ===========================================================================
  # Identidad gestionada (mejor práctica vs Service Principal)
  # ===========================================================================
  identity {
    type = "SystemAssigned"
  }

  # ===========================================================================
  # Networking: Azure CNI Overlay + Cilium
  # Ventajas:
  #   - No consume IPs del VNet para pods (usa overlay 10.244.x.x)
  #   - Cilium provee eBPF networking: mayor rendimiento, NetworkPolicies avanzadas
  #   - Compatible con Hubble para observabilidad de red
  # ===========================================================================
  network_profile {
    network_plugin      = "azure"          # Azure CNI
    network_plugin_mode = "overlay"        # Overlay: pods no consumen IPs del VNet
    network_data_plane  = "cilium"         # ← Cilium como dataplane eBPF
    network_policy      = "cilium"         # ← Cilium NetworkPolicy
    pod_cidr            = "10.244.0.0/16"  # CIDR para pods (overlay)
    service_cidr        = "10.96.0.0/16"  # CIDR para services de Kubernetes
    dns_service_ip      = "10.96.0.10"    # IP del CoreDNS (debe estar en service_cidr)
    outbound_type       = "loadBalancer"   # Usar "userDefinedRouting" con hub-spoke/firewall
    load_balancer_sku   = "standard"       # Standard requerido para zonas de disponibilidad
  }

  # ===========================================================================
  # RBAC y Azure AD Integration
  # ===========================================================================
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    managed                 = true   # AKS gestiona los roles integrados (cluster-admin, etc.)    
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true   # Azure RBAC en lugar de Kubernetes RBAC nativo
    admin_group_object_ids = [var.aks_admin_group_id] # ← Habilitar con AD group real
  }

  # ===========================================================================
  # Add-ons del cluster
  # ===========================================================================

  # AGIC: Application Gateway Ingress Controller (dominio público)
  # ingress_application_gateway {
  #   gateway_id = azurerm_application_gateway.main.id
  # }

  # Azure Monitor / Container Insights
  # oms_agent {
  #  log_analytics_workspace_id      = var.log_analytics_workspace_id
  #  msi_auth_for_monitoring_enabled = true  # Usar identidad en lugar de clave
  #}

  # Azure Key Vault Secrets Store (para montar secrets como volúmenes)
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Azure Policy para Kubernetes (Gatekeeper integrado)
  azure_policy_enabled = true

  # ===========================================================================
  # Seguridad del cluster
  # ===========================================================================

  # Defender for Containers (Microsoft Defender)
  #microsoft_defender {
  #  log_analytics_workspace_id = var.log_analytics_workspace_id
  #}

  # Deshabilitar dashboard legacy de Kubernetes
  http_application_routing_enabled = false

  # Perfil de seguridad del cluster
  storage_profile {
    blob_driver_enabled         = true   # Para Azure Blob CSI
    disk_driver_enabled         = true   # Para Azure Disk CSI
    file_driver_enabled         = true   # Para Azure Files CSI
    snapshot_controller_enabled = true   # Para VolumeSnapshots
  }

  # Workload Identity (reemplaza a Pod Identity)
  workload_identity_enabled = true
  oidc_issuer_enabled       = true   # Requerido para Workload Identity

  tags = var.tags
}

# ===========================================================================
# User Node Pool - Cargas de trabajo de aplicaciones
# ===========================================================================
resource "azurerm_kubernetes_cluster_node_pool" "workload" {
  name                  = var.user_node_pool.name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_pool.vm_size
  zones                 = var.availability_zones    # ← 3 AZs
  enable_auto_scaling  = true
  min_count             = var.user_node_pool.min_count
  max_count             = var.user_node_pool.max_count
  os_disk_size_gb       = var.user_node_pool.os_disk_size_gb
  os_disk_type          = var.user_node_pool.os_disk_type
  max_pods              = var.user_node_pool.max_pods
  vnet_subnet_id        = var.aks_subnet_id
  mode                  = "User"

  upgrade_settings {
    max_surge                     = "1"
    drain_timeout_in_minutes      = 30
    node_soak_duration_in_minutes = 0
  }

  node_labels = merge(var.user_node_pool.node_labels, {
    "environment" = var.environment
  })

  node_taints = var.user_node_pool.node_taints

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Role Assignments para la identidad del cluster AKS
# Network Contributor: necesario para gestionar IPs y NSGs en la subnet
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# ACR Pull: si tienes un Azure Container Registry
# resource "azurerm_role_assignment" "aks_acr_pull" {
#   scope                = var.acr_id
#   role_definition_name = "AcrPull"
#   principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
# }
