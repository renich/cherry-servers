# =============================================================================
# 3. Recursos de Infraestructura: Clúster Garage S3 de 3 Nodos
# =============================================================================

# Paso 1: Registra tu clave pública SSH en el proyecto de Cherry Servers (si no reutilizas ssh_key_id)
resource "cherryservers_ssh_key" "deployer" {
  count      = trimspace(var.ssh_key_id) == "" ? 1 : 0
  name       = "garage-deployer-key"
  public_key = trimspace(var.ssh_public_key)

  lifecycle {
    precondition {
      condition     = trimspace(var.ssh_key_id) != "" || trimspace(var.ssh_public_key) != ""
      error_message = "Debes proporcionar ssh_key_id o ssh_public_key para acceder por SSH."
    }
  }
}

# Paso 2: Genera secretos criptográficos efímeros para el clúster (RPC y Admin API)
resource "random_id" "rpc_secret" {
  byte_length = 32
}

resource "random_id" "admin_token" {
  byte_length = 32
}

# Paso 3: Aprovisiona el Nodo 0 (Zona z1 + Puerta de Enlace HTTPS con Caddy)
resource "cherryservers_server" "garage_node_0" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.node0_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [local.active_ssh_key_id]

  user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap-node0.bash", {
    NODE_NAME      = var.node0_name
    GARAGE_VERSION = var.garage_version
    RPC_SECRET     = random_id.rpc_secret.hex
    ADMIN_TOKEN    = random_id.admin_token.hex
  })) : null

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Garage-S3"
    Zone        = "z1"
  }
}

locals {
  active_ssh_key_id = trimspace(var.ssh_key_id) == "" ? cherryservers_ssh_key.deployer[0].id : trimspace(var.ssh_key_id)
  node0_public_ip   = one([for ip in cherryservers_server.garage_node_0.ip_addresses : ip.address if ip.type == "primary-ip"])
  node0_private_ip  = one([for ip in cherryservers_server.garage_node_0.ip_addresses : ip.address if ip.type == "private-ip"])
  node1_public_ip   = one([for ip in cherryservers_server.garage_node_1.ip_addresses : ip.address if ip.type == "primary-ip"])
  node1_private_ip  = one([for ip in cherryservers_server.garage_node_1.ip_addresses : ip.address if ip.type == "private-ip"])
  node2_public_ip   = one([for ip in cherryservers_server.garage_node_2.ip_addresses : ip.address if ip.type == "primary-ip"])
  node2_private_ip  = one([for ip in cherryservers_server.garage_node_2.ip_addresses : ip.address if ip.type == "private-ip"])
}

# Paso 4: Aprovisiona el Nodo 1 (Zona z2) conectándose al Nodo 0 por la VLAN privada
resource "cherryservers_server" "garage_node_1" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.node1_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [local.active_ssh_key_id]

  user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap-peer.bash", {
    NODE_NAME        = var.node1_name
    GARAGE_VERSION   = var.garage_version
    RPC_SECRET       = random_id.rpc_secret.hex
    ADMIN_TOKEN      = random_id.admin_token.hex
    NODE0_PRIVATE_IP = coalesce(local.node0_private_ip, "")
  })) : null

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Garage-S3"
    Zone        = "z2"
  }
}

# Paso 5: Aprovisiona el Nodo 2 (Zona z3) conectándose al Nodo 0 por la VLAN privada
resource "cherryservers_server" "garage_node_2" {
  project_id    = var.project_id
  region        = var.region
  plan          = var.server_plan
  image         = var.server_image
  hostname      = var.node2_name
  spot_instance = var.spot_instance
  ssh_key_ids   = [local.active_ssh_key_id]

  user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap-peer.bash", {
    NODE_NAME        = var.node2_name
    GARAGE_VERSION   = var.garage_version
    RPC_SECRET       = random_id.rpc_secret.hex
    ADMIN_TOKEN      = random_id.admin_token.hex
    NODE0_PRIVATE_IP = coalesce(local.node0_private_ip, "")
  })) : null

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Service     = "Garage-S3"
    Zone        = "z3"
  }
}
