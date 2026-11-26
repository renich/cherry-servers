# =============================================================================
# 4. Salidas del Despliegue
# =============================================================================
# Datos que OpenTofu imprime en tu terminal cuando la creación concluye.

locals {
  # Obtiene la dirección IPv4 pública principal asignada por Cherry Servers
  primary_ip       = one([for ip in cherryservers_server.caddy_node.ip_addresses : ip.address if ip.type == "primary-ip"])
  effective_domain = var.vault_domain != "" && var.vault_domain != "auto" ? var.vault_domain : "${local.primary_ip}.sslip.io"
}

output "server_ip" {
  description = "Dirección IP pública del servidor"
  value       = local.primary_ip
}

output "vault_domain" {
  description = "Nombre de dominio FQDN asignado para Vaultwarden"
  value       = local.effective_domain
}

output "vaultwarden_url" {
  description = "URL HTTPS de acceso a Vaultwarden; usa Let's Encrypt en dominios públicos o sslip.io y tls internal en dominios privados o locales"
  value       = "https://${local.effective_domain}"
}

output "ssh_command" {
  description = "Comando directo para acceder a la terminal del servidor por SSH"
  value       = "ssh root@${local.primary_ip}"
}
