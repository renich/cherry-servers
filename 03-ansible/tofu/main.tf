# =============================================================================
# 3. Recursos de Infraestructura (Flujo Lineal y Plano)
# =============================================================================

# Paso 1: Registra tu clave pública SSH en el proyecto de Cherry Servers
resource "cherryservers_ssh_key" "deployer" {
  name       = "ansible-deployer-key"
  public_key = var.ssh_public_key
}

# Paso 2: Aprovisiona la máquina virtual en la nube con CentOS Stream 10
resource "cherryservers_server" "ansible_node" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.server_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [cherryservers_ssh_key.deployer.id]

  # Etiquetas de metadatos para organizar los recursos en tu cuenta
  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Ansible-Automation"
  }
}
