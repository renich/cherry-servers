# =============================================================================
# 1. Configuración del Proveedor (Cherry Servers)
# =============================================================================
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    cherryservers = {
      source  = "cherryservers/cherryservers"
      version = "~> 1.5.3"
    }
  }
}

provider "cherryservers" {
  api_token = var.cherry_auth_token
}
