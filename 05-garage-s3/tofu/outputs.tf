# =============================================================================
# 4. Salidas del Despliegue
# =============================================================================

output "node0_public_ip" {
  description = "Dirección IPv4 pública del Nodo 0: 0.garage.linenes.tld"
  value       = local.node0_public_ip
}

output "node0_private_ip" {
  description = "Dirección IPv4 privada del Nodo 0 en la VLAN interna"
  value       = local.node0_private_ip
}

output "node1_public_ip" {
  description = "Dirección IPv4 pública del Nodo 1: 1.garage.linenes.tld"
  value       = local.node1_public_ip
}

output "node1_private_ip" {
  description = "Dirección IPv4 privada del Nodo 1 en la VLAN interna"
  value       = local.node1_private_ip
}

output "node2_public_ip" {
  description = "Dirección IPv4 pública del Nodo 2: 2.garage.linenes.tld"
  value       = local.node2_public_ip
}

output "node2_private_ip" {
  description = "Dirección IPv4 privada del Nodo 2 en la VLAN interna"
  value       = local.node2_private_ip
}

output "ssh_node0_command" {
  description = "Comando SSH hacia el Nodo 0"
  value       = "ssh root@${local.node0_public_ip}"
}

output "ssh_node1_command" {
  description = "Comando SSH hacia el Nodo 1"
  value       = "ssh root@${local.node1_public_ip}"
}

output "ssh_node2_command" {
  description = "Comando SSH hacia el Nodo 2"
  value       = "ssh root@${local.node2_public_ip}"
}

output "s3_endpoint_url" {
  description = "Punto de entrada HTTPS oficial con Let's Encrypt para la API S3"
  value       = "https://s3.${local.node0_public_ip}.sslip.io"
}

output "web_endpoint_url" {
  description = "Punto de entrada HTTPS oficial con Let's Encrypt para el sitio web estático en el bucket sitio"
  value       = "https://web.${local.node0_public_ip}.sslip.io"
}

output "credentials_command" {
  description = "Comando para consultar el archivo de credenciales S3 generadas en el Nodo 0"
  value       = "ssh root@${local.node0_public_ip} cat /root/garage-credentials.txt"
}
