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
  default     = "LT-Siauliai" # Lituania (máxima disponibilidad y menor latencia en Europa)
  description = "Slug de la región geográfica en Cherry Servers"
}

variable "server_plan" {
  type        = string
  default     = "B2-2-2gb-40s-shared" # Cloud VPS 2 (Gen 2: 2 vCores/2 GB RAM/40GB SSD)
  description = "Slug del plan de cómputo en Cherry Servers"
}

variable "ssh_public_key" {
  type        = string
  description = "Tu clave pública SSH para acceder de forma segura sin contraseña"
}

variable "server_name" {
  type        = string
  default     = "0.luanti.linenes.tld"
  description = "FQDN estructurado del servidor (nodo.servicio.entorno.tld)"
}

variable "spot_instance" {
  type        = bool
  default     = false
  description = "Desplegar como instancia Spot con descuento en precio por hora"
}
