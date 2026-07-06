# =============================================================================
# locals.tf - Valores locales y tags comunes
# =============================================================================

locals {
  # Tags obligatorios según buenas prácticas de Azure CAF (Cloud Adoption Framework)
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Location    = var.location
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
    # CreatedAt   = timestamp()
  }

  # Nombre base usado en múltiples recursos
  resource_prefix = "${var.project}-${var.environment}-${var.location_short}"
}
