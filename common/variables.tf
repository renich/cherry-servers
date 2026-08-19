# =============================================================================
# Variables Compartidas de OpenTofu (Cherry Servers)
# =============================================================================

variable "cherry_auth_token" {
  description = "Token de autenticación de la API de Cherry Servers (o variable de entorno CHERRY_AUTH_TOKEN)"
  type        = string
  sensitive   = true
}

variable "project_id" {
  description = "ID numérico del proyecto en Cherry Servers"
  type        = number
}

variable "region" {
  description = "Región de despliegue por defecto (Lituania/región UE para óptima disponibilidad y costo Spot)"
  type        = string
  default     = "LT-Siauliai"
}

variable "ssh_key_id" {
  description = "ID de la clave SSH registrada en el proyecto de Cherry Servers"
  type        = string
  default     = ""
}

variable "spot_instance" {
  description = "Desplegar como instancia Spot con descuento en precio por hora"
  type        = bool
  default     = false
}
