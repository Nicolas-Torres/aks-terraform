# =============================================================================
# outputs.tf - Outputs del módulo raíz
# =============================================================================

output "resource_group_name" {
  description = "Nombre del Resource Group principal"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID del Virtual Network"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Nombre del Virtual Network"
  value       = module.networking.vnet_name
}

output "aks_subnet_id" {
  description = "ID de la subnet de nodos AKS"
  value       = module.networking.aks_subnet_id
}

output "aks_cluster_id" {
  description = "ID del cluster AKS"
  value       = module.aks.cluster_id
}

output "aks_cluster_name" {
  description = "Nombre del cluster AKS"
  value       = module.aks.cluster_name
}

output "aks_fqdn" {
  description = "FQDN del API server del cluster AKS"
  value       = module.aks.cluster_fqdn
}

output "aks_identity_principal_id" {
  description = "Principal ID de la identidad gestionada del cluster AKS"
  value       = module.aks.kubelet_identity_principal_id
}

# output "appgw_public_ip" {
#   description = "IP pública del Application Gateway (Ingress)"
#   value       = module.aks.appgw_public_ip
# }

# output "appgw_public_ip_fqdn" {
#   description = "FQDN de la IP pública del Application Gateway"
#   value       = module.aks.appgw_public_ip_fqdn
# }

# Comando para obtener las credenciales del cluster
output "get_credentials_command" {
  description = "Comando para obtener kubeconfig del cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name} --overwrite-existing"
}

output "aks_principal_id" {
  value = module.aks.aks_identity_principal_id
}

# output "agic_identity_object_id" {
#   description = "Object ID de la identidad gestionada del addon AGIC (debe coincidir con el object id del error 403)"
#   value       = module.aks.agic_identity_object_id
# }

# output "agic_identity_client_id" {
#   description = "Client ID de la identidad gestionada del addon AGIC (debe coincidir con el client id del error 403)"
#   value       = module.aks.agic_identity_client_id
# }

# output "agic_appgw_contributor_role_assignment_id" {
#   description = "ID del role assignment Contributor sobre el Application Gateway"
#   value       = module.aks.agic_appgw_contributor_role_assignment_id
# }

# output "agic_rg_reader_role_assignment_id" {
#   description = "ID del role assignment Reader sobre el Resource Group"
#   value       = module.aks.agic_rg_reader_role_assignment_id
# }
