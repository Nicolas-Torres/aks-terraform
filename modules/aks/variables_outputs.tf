# =============================================================================
# modules/aks/variables.tf
# =============================================================================

variable "resource_group_name"     { type = string }
variable "location"                { type = string }
variable "project"                 { type = string }
variable "environment"             { type = string }
variable "location_short"          { type = string }
variable "vnet_id"                 { type = string }
variable "aks_subnet_id"           { type = string }
variable "appgw_subnet_id"         { type = string }
variable "kubernetes_version"      { type = string }
variable "availability_zones"      { type = list(string) }
variable "system_node_pool"        { type = any }
variable "user_node_pool"          { type = any }
variable "dns_prefix"              {
  type = string
  default = null
}
variable "private_cluster_enabled" {
  type = bool
  default = false
}
variable "tenant_id"               { type = string }
variable "tags"                    { type = map(string) }

variable "log_analytics_workspace_id" {
  description = "ID del Log Analytics Workspace para Container Insights"
  type        = string
  default     = ""
}

variable "aks_admin_group_id"       { type = string }

# =============================================================================
# modules/aks/outputs.tf
# =============================================================================

output "cluster_id"   { value = azurerm_kubernetes_cluster.main.id }
output "cluster_name" { value = azurerm_kubernetes_cluster.main.name }
output "cluster_fqdn" { value = azurerm_kubernetes_cluster.main.fqdn }

output "kubelet_identity_principal_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "URL del OIDC issuer para Workload Identity"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

# output "appgw_public_ip" {
#   value = azurerm_public_ip.appgw.ip_address
# }

# output "appgw_public_ip_fqdn" {
#   description = "FQDN automático de Azure para la IP pública del ingress"
#   value       = azurerm_public_ip.appgw.fqdn
# }

# output "appgw_id" { value = azurerm_application_gateway.main.id }

output "kube_config" {
  value     = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive = true
}
