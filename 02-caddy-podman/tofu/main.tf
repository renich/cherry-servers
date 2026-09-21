# =============================================================================
# 3. Recursos de Infraestructura (Flujo Lineal y Plano)
# =============================================================================

# Paso 1: Registramos tu clave pública SSH en el proyecto de Cherry Servers
resource "cherryservers_ssh_key" "deployer" {
  name       = "caddy-deployer-key"
  public_key = var.ssh_public_key
}

locals {
  # Si el dominio termina en .tld, .lan, .local, .internal o .lab, habilitamos TLS interno auto-firmado
  is_lab_domain = can(regex("\\.(tld|lan|local|internal|lab)$", var.vault_domain))
  tls_directive = local.is_lab_domain ? "tls internal" : ""
}

# Paso 2: Aprovisionamos la máquina virtual en la nube con CentOS Stream 10
resource "cherryservers_server" "caddy_node" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.server_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [cherryservers_ssh_key.deployer.id]

  # Inyectamos el script de arranque codificado en Base64 (requerido por Cherry Servers) si enable_bootstrap es true
  user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap.bash", {
    SERVER_NAME   = var.server_name
    VAULT_DOMAIN  = var.vault_domain
    TLS_DIRECTIVE = local.tls_directive
  })) : null

  # Etiquetas de metadatos para organizar los recursos en tu cuenta
  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Caddy-Vaultwarden"
  }
}
