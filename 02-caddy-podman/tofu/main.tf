# =============================================================================
# 3. Recursos de Infraestructura: Flujo Lineal y Plano
# =============================================================================

# Paso 1: Registra tu clave pública SSH en Cherry Servers si no reutilizas ssh_key_id
resource "cherryservers_ssh_key" "deployer" {
  count      = trimspace(var.ssh_key_id) == "" ? 1 : 0
  name       = "caddy-deployer-key"
  public_key = trimspace(var.ssh_public_key)

  lifecycle {
    precondition {
      condition     = trimspace(var.ssh_key_id) != "" || trimspace(var.ssh_public_key) != ""
      error_message = "Debes proporcionar ssh_key_id o ssh_public_key para acceder por SSH."
    }
  }
}

locals {
  active_ssh_key_id = trimspace(var.ssh_key_id) != "" ? trimspace(var.ssh_key_id) : cherryservers_ssh_key.deployer[0].id
  # Si el dominio termina en .tld, .lan, .local, .internal o .lab, habilita TLS interno autofirmado
  is_lab_domain = can(regex("\\.(tld|lan|local|internal|lab)$", var.vault_domain))
  tls_directive = local.is_lab_domain ? "tls internal" : ""
}

# Paso 2: Aprovisiona la máquina virtual en la nube con CentOS Stream 10
resource "cherryservers_server" "caddy_node" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.server_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [local.active_ssh_key_id]

  # Inyecta el script de arranque codificado en Base64 requerido por Cherry Servers si enable_bootstrap es true
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
