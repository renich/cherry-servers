# =============================================================================
# 3. Recursos de Infraestructura (Flujo Lineal y Plano)
# =============================================================================

# Paso 1: Registra tu clave pública SSH en el proyecto de Cherry Servers
resource "cherryservers_ssh_key" "deployer" {
  name       = "primitives-deployer-key"
  public_key = var.ssh_public_key
}

# Paso 2: Aprovisiona el Nodo Servidor de Primitivas (DNS BIND 9, NTP Chrony y NFSv4.2)
resource "cherryservers_server" "primitivas_server" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.server_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [cherryservers_ssh_key.deployer.id]

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
  # Extrae las direcciones IP pública y privada del nodo servidor principal
  server_public_ip  = one([for ip in cherryservers_server.primitivas_server.ip_addresses : ip.address if ip.type == "primary-ip"])
  server_private_ip = one([for ip in cherryservers_server.primitivas_server.ip_addresses : ip.address if ip.type == "private-ip"])
  client_public_ip  = one([for ip in cherryservers_server.primitivas_client.ip_addresses : ip.address if ip.type == "primary-ip"])
  client_private_ip = one([for ip in cherryservers_server.primitivas_client.ip_addresses : ip.address if ip.type == "private-ip"])
}

# Paso 3: Aprovisiona el Nodo Cliente (consumidor de DNS, NTP y montaje NFSv4.2)
resource "cherryservers_server" "primitivas_client" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.client_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [cherryservers_ssh_key.deployer.id]

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
