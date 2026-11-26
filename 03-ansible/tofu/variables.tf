# =============================================================================
# 2. Definición de Variables de Entrada
# =============================================================================
# Parámetros configurables por el usuario sin necesidad de modificar el código.

variable "cherry_auth_token" {
  type        = string
  description = "Tu API Token de autenticación de Cherry Servers"
  sensitive   = true
}

variable "project_id" {
  type        = number
  description = "El ID numérico del proyecto en Cherry Servers donde se creará el servidor"
}

variable "region" {
  type        = string
  default     = "LT-Siauliai"
  description = "Slug de la región geográfica en Cherry Servers"
}

variable "server_plan" {
  type        = string
  default     = "B1-1-1gb-20s-shared"
  description = "Slug del plan de cómputo en Cherry Servers: Cloud VPS 1, ~$0.015 EUR/hr"
}

variable "server_image" {
  type        = string
  default     = "centos_stream_10_64bit"
  description = "Slug de la imagen del sistema operativo en Cherry Servers, CentOS Stream 10 por defecto"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Tu clave pública SSH Ed25519 para acceder de forma segura sin contraseña"
}

variable "ssh_key_id" {
  type        = string
  default     = ""
  description = "ID de clave SSH existente en Cherry Servers para reutilizar sin recrearla"
}

variable "server_name" {
  type        = string
  default     = "0.ansible.linenes.tld"
  description = "FQDN estructurado del nodo servidor"
}

variable "spot_instance" {
  type        = bool
  default     = false
  description = "Desplegar como instancia Spot con descuento en precio por hora"
}
