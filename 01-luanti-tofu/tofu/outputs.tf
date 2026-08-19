# =============================================================================
# 4. Salidas del Despliegue (Outputs)
# =============================================================================
# Datos que OpenTofu nos imprime en la terminal cuando la creación concluye.

locals {
  # Obtenemos la dirección IPv4 pública principal asignada por Cherry Servers
  primary_ip = one([for ip in cherryservers_server.luanti_node.ip_addresses : ip.address if ip.type == "primary-ip"])
}

output "server_ip" {
  description = "Dirección IP pública del servidor"
  value       = local.primary_ip
}

output "connection_string" {
  description = "Dirección para conectar directamente en el cliente de Luanti"
  value       = "${local.primary_ip}:30000"
}

output "ssh_command" {
  description = "Comando directo para acceder a la terminal del servidor por SSH"
  value       = "ssh root@${local.primary_ip}"
}
