output "aks_identity_principal_id" {
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
  description = "Principal ID de la identidad SystemAssigned del AKS"
}

# Identidad administrada que crea automáticamente el addon AGIC
# (ingressapplicationgateway-<cluster>). Comparar estos valores contra el
# client_id/object_id que reporta el error 403 de Azure para confirmar que
# el role assignment apunta a la identidad correcta.
# output "agic_identity_object_id" {
#   value       = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
#   description = "Object ID de la identidad gestionada del addon AGIC"
# }

# output "agic_identity_client_id" {
#   value       = azurerm_kubernetes_cluster.main.ingress_application_gateway[0].ingress_application_gateway_identity[0].client_id
#   description = "Client ID de la identidad gestionada del addon AGIC"
# }

# output "agic_appgw_contributor_role_assignment_id" {
#   value       = azurerm_role_assignment.agic_appgw_contributor.id
#   description = "ID del role assignment Contributor sobre el Application Gateway"
# }

# output "agic_rg_reader_role_assignment_id" {
#   value       = azurerm_role_assignment.agic_rg_reader.id
#   description = "ID del role assignment Reader sobre el Resource Group"
# }
