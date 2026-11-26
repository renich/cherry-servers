# =============================================================================
# 2. Definición de Variables de Entrada
# =============================================================================

variable "cherry_auth_token" {
  type        = string
  description = "Tu API Token de autenticación de Cherry Servers"
  sensitive   = true
}

variable "project_id" {
  type        = number
  description = "El ID numérico del proyecto en Cherry Servers donde se desplegará el clúster"
}

variable "region" {
  type        = string
  default     = "LT-Siauliai"
  description = "Identificador de la región geográfica en Cherry Servers"
}

variable "server_plan" {
  type        = string
  default     = "B1-1-1gb-20s-shared"
  description = "Identificador del plan de cómputo en Cherry Servers: 3x Cloud VPS 1, ~$0.045 EUR/hr"
}

variable "server_image" {
  type        = string
  default     = "centos_stream_10_64bit"
  description = "Identificador de la imagen del sistema operativo, CentOS Stream 10 por defecto"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Tu clave pública SSH Ed25519 para acceso remoto sin contraseña"
}

variable "ssh_key_id" {
  type        = string
  default     = ""
  description = "ID de clave SSH existente en Cherry Servers para reutilizar sin recrearla"
}

variable "node0_name" {
  type        = string
  default     = "0.garage.linenes.tld"
  description = "FQDN estructurado del Nodo 0: almacenamiento y puerta de enlace TLS con Caddy"
}

variable "node1_name" {
  type        = string
  default     = "1.garage.linenes.tld"
  description = "FQDN estructurado del Nodo 1: almacenamiento en zona z2"
}

variable "node2_name" {
  type        = string
  default     = "2.garage.linenes.tld"
  description = "FQDN estructurado del Nodo 2: almacenamiento en zona z3"
}

variable "garage_version" {
  type        = string
  default     = "v2.6.0"
  description = "Etiqueta exacta de la imagen oficial dxflrs/garage"
}

variable "spot_instance" {
  type        = bool
  default     = false
  description = "Desplegar como instancias Spot con descuento en precio por hora"
}

variable "enable_bootstrap" {
  type        = bool
  default     = true
  description = "Ejecutar el aprovisionamiento automático en cloud-init; usa false para práctica manual paso a paso"
}
