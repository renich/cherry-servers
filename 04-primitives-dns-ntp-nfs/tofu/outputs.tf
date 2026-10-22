# =============================================================================
# 4. Salidas del Despliegue (Outputs)
# =============================================================================
# Datos que OpenTofu imprime en la terminal cuando la creación concluye.

output "server_public_ip" {
  description = "Dirección IPv4 pública del nodo servidor de primitivas (DNS, NTP, NFS)"
  value       = local.server_public_ip
}

output "server_private_ip" {
  description = "Dirección IPv4 privada interna del nodo servidor de primitivas"
  value       = local.server_private_ip
}

output "client_public_ip" {
  description = "Dirección IPv4 pública del nodo cliente"
  value       = local.client_public_ip
}

output "client_private_ip" {
  description = "Dirección IPv4 privada interna del nodo cliente"
  value       = local.client_private_ip
}

output "ssh_server_command" {
  description = "Comando directo para conectarse por SSH al nodo servidor (0.primitivas.linenes.tld)"
  value       = "ssh root@${local.server_public_ip}"
}

output "ssh_client_command" {
  description = "Comando directo para conectarse por SSH al nodo cliente (1.primitivas.linenes.tld)"
  value       = "ssh root@${local.client_public_ip}"
}
