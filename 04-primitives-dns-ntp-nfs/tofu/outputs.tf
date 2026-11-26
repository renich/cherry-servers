# =============================================================================
# 4. Salidas del Despliegue
# =============================================================================
# Datos que OpenTofu imprime en la terminal cuando concluye el aprovisionamiento.

output "server_public_ip" {
  description = "Dirección IPv4 pública del Nodo 0: servidor de DNS, NTP y NFSv4.2"
  value       = local.server_public_ip
}

output "server_private_ip" {
  description = "Dirección IPv4 privada interna del Nodo 0"
  value       = local.server_private_ip
}

output "client_public_ip" {
  description = "Dirección IPv4 pública del Nodo 1: cliente de verificación"
  value       = local.client_public_ip
}

output "client_private_ip" {
  description = "Dirección IPv4 privada interna del Nodo 1"
  value       = local.client_private_ip
}

output "ssh_server_command" {
  description = "Comando directo para conectarse por SSH al Nodo 0"
  value       = "ssh root@${local.server_public_ip}"
}

output "ssh_client_command" {
  description = "Comando directo para conectarse por SSH al Nodo 1"
  value       = "ssh root@${local.client_public_ip}"
}
