# =============================================================================
# 3. Recursos de Infraestructura: Flujo Lineal y Plano
# =============================================================================

# Paso 1: Registra tu clave pública SSH en Cherry Servers si no reutilizas ssh_key_id
resource "cherryservers_ssh_key" "deployer" {
  count      = trimspace(var.ssh_key_id) == "" ? 1 : 0
  name       = "primitives-deployer-key"
  public_key = trimspace(var.ssh_public_key)

  lifecycle {
    precondition {
      condition     = trimspace(var.ssh_key_id) != "" || trimspace(var.ssh_public_key) != ""
      error_message = "Debes proporcionar ssh_key_id o ssh_public_key para acceder por SSH."
    }
  }
}

# Paso 2: Aprovisiona el Nodo 0, servidor de primitivas DNS, NTP y NFSv4.2
resource "cherryservers_server" "primitivas_server" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.server_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [local.active_ssh_key_id]

  user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap.bash", {
    SERVER_NAME = var.server_name
    DNS_DOMAIN  = var.dns_domain
  })) : null

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Primitives-DNS-NTP-NFS"
    Role        = "Server"
  }
}

locals {
  active_ssh_key_id = trimspace(var.ssh_key_id) != "" ? trimspace(var.ssh_key_id) : cherryservers_ssh_key.deployer[0].id
  server_public_ip  = one([for ip in cherryservers_server.primitivas_server.ip_addresses : ip.address if ip.type == "primary-ip"])
  server_private_ip = one([for ip in cherryservers_server.primitivas_server.ip_addresses : ip.address if ip.type == "private-ip"])
  client_public_ip  = one([for ip in cherryservers_server.primitivas_client.ip_addresses : ip.address if ip.type == "primary-ip"])
  client_private_ip = one([for ip in cherryservers_server.primitivas_client.ip_addresses : ip.address if ip.type == "private-ip"])
}

# Paso 3: Aprovisiona el Nodo 1, cliente consumidor de DNS, NTP y montaje NFSv4.2
resource "cherryservers_server" "primitivas_client" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.client_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [local.active_ssh_key_id]

  user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap-client.bash", {
    CLIENT_NAME       = var.client_name
    DNS_DOMAIN        = var.dns_domain
    SERVER_PRIVATE_IP = coalesce(local.server_private_ip, "")
    SERVER_PUBLIC_IP  = coalesce(local.server_public_ip, "")
  })) : null

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Primitives-DNS-NTP-NFS"
    Role        = "Client"
  }
}
