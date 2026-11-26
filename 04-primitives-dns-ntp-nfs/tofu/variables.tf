# =============================================================================
# 2. Definición de Variables de Entrada
# =============================================================================
# Parámetros configurables sin modificar la lógica de los manifiestos.

variable "cherry_auth_token" {
  type        = string
  description = "Tu API Token de autenticación de Cherry Servers"
  sensitive   = true
}

variable "project_id" {
  type        = number
  description = "Identificador numérico del proyecto en Cherry Servers donde se crearán los servidores"
}

variable "region" {
  type        = string
  default     = "LT-Siauliai"
  description = "Identificador de la región geográfica en Cherry Servers"
}

variable "server_plan" {
  type        = string
  default     = "B1-1-1gb-20s-shared"
  description = "Identificador del plan de cómputo en Cherry Servers: Cloud VPS 1 Gen 2, ~$0.015 EUR/hr por nodo"
}

variable "server_image" {
  type        = string
  default     = "centos_stream_10_64bit"
  description = "Identificador de la imagen del sistema operativo en Cherry Servers, CentOS Stream 10 por defecto"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Tu clave pública SSH Ed25519 para acceder de forma segura sin contraseña"
}

variable "ssh_key_id" {
  type        = string
  default     = ""
  description = "Identificador de una clave SSH existente en Cherry Servers para reutilizarla sin recrearla"
}

variable "server_name" {
  type        = string
  default     = "0.primitivas.linenes.tld"
  description = "FQDN estructurado del Nodo 0: servidor principal de DNS, NTP y NFSv4.2"
}

variable "client_name" {
  type        = string
  default     = "1.primitivas.linenes.tld"
  description = "FQDN estructurado del Nodo 1: cliente de verificación"
}

variable "dns_domain" {
  type        = string
  default     = "linenes.tld"
  description = "Dominio DNS autoritativo interno para el laboratorio"
}

variable "spot_instance" {
  type        = bool
  default     = false
  description = "Desplegar como instancias Spot con descuento en precio por hora"
}

variable "enable_bootstrap" {
  type        = bool
  default     = true
  description = "Ejecutar los scripts de aprovisionamiento automáticamente al arrancar; usa false para práctica manual paso a paso"
}
