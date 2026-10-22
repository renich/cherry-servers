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
  description = "El ID numérico del proyecto en Cherry Servers donde se crearán los servidores"
}

variable "region" {
  type        = string
  default     = "LT-Siauliai" # Lituania (máxima disponibilidad y menor latencia en Europa)
  description = "Slug de la región geográfica en Cherry Servers"
}

variable "server_plan" {
  type        = string
  default     = "B1-1-1gb-20s-shared" # Cloud VPS 1 (Gen 2: 1 vCore/1 GB RAM/20GB SSD, ~$0.015 EUR/hr por nodo)
  description = "Slug del plan de cómputo en Cherry Servers"
}

variable "server_image" {
  type        = string
  default     = "centos_stream_10_64bit"
  description = "Slug de la imagen del sistema operativo en Cherry Servers (CentOS Stream 10 por defecto)"
}

variable "ssh_public_key" {
  type        = string
  description = "Tu clave pública SSH Ed25519 para acceder de forma segura sin contraseña"
}

variable "server_name" {
  type        = string
  default     = "0.primitivas.linenes.tld"
  description = "FQDN estructurado del nodo servidor principal (DNS, NTP y NFSv4)"
}

variable "client_name" {
  type        = string
  default     = "1.primitivas.linenes.tld"
  description = "FQDN estructurado del nodo cliente de verificación"
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
  description = "Ejecutar los scripts de bootstrap automáticamente al arrancar (false para laboratorios manuales paso a paso)"
}
