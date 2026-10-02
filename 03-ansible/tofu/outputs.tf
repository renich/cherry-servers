# =============================================================================
# 4. Salidas del Despliegue (Outputs)
# =============================================================================
# Datos que OpenTofu imprime en la terminal cuando la creación concluye.

locals {
  # Obtiene la dirección IPv4 pública principal asignada por Cherry Servers
  primary_ip = one([for ip in cherryservers_server.ansible_node.ip_addresses : ip.address if ip.type == "primary-ip"])
}

output "server_ip" {
  description = "Dirección IPv4 pública asignada al servidor"
  value       = local.primary_ip
}

output "ssh_command" {
  description = "Comando SSH directo para conectarse a la terminal del servidor"
  value       = "ssh root@${local.primary_ip}"
}

output "web_url" {
  description = "URL del servicio web desplegado mediante el Playbook de Ansible"
  value       = "http://${local.primary_ip}"
}

output "ansible_playbook_command" {
  description = "Comando para ejecutar el playbook de Ansible contra el nodo desplegado"
  value       = "ansible-playbook -i inventory.ini playbook.yml"
}
