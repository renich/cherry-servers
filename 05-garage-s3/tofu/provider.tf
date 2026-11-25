# =============================================================================
# 1. Configuración de OpenTofu y Proveedor Oficial de Cherry Servers
# =============================================================================
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    cherryservers = {
      source  = "cherryservers/cherryservers"
      version = "~> 1.5.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "cherryservers" {
  api_token = var.cherry_auth_token
}
