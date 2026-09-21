# =============================================================================
# 4. Salidas del Despliegue (Outputs)
# =============================================================================
# Datos que OpenTofu nos imprime en la terminal cuando la creación concluye.

locals {
  # Obtenemos la dirección IPv4 pública principal asignada por Cherry Servers
  primary_ip = one([for ip in cherryservers_server.caddy_node.ip_addresses : ip.address if ip.type == "primary-ip"])
}

output "server_ip" {
  description = "Dirección IP pública del servidor"
  value       = local.primary_ip
}

output "vault_domain" {
  description = "Nombre de dominio FQDN asignado para Vaultwarden"
  value       = var.vault_domain
}

output "vaultwarden_url" {
  description = "URL segura de acceso a la interfaz web de Vaultwarden"
  value       = "https://${var.vault_domain}"
}

output "hosts_entry" {
  description = "Línea para agregar a /etc/hosts en tu máquina local si usas un dominio de prueba"
  value       = "${local.primary_ip} ${var.vault_domain}"
}

output "ssh_command" {
  description = "Comando directo para acceder a la terminal del servidor por SSH"
  value       = "ssh root@${local.primary_ip}"
}
