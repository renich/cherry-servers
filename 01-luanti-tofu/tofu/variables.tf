# =============================================================================
# 2. Definición de Variables de Entrada
# =============================================================================
# Parámetros configurables sin necesidad de modificar los manifiestos.

variable "cherry_auth_token" {
  type        = string
  description = "Tu token de API para autenticarte en Cherry Servers"
  sensitive   = true
}

variable "project_id" {
  type        = number
  description = "Identificador numérico del proyecto en Cherry Servers donde se creará el servidor"
}

variable "region" {
  type        = string
  default     = "LT-Siauliai" # Lituania: alta disponibilidad y baja latencia en Europa
  description = "Identificador de la región geográfica en Cherry Servers"
}

variable "server_plan" {
  type        = string
  default     = "B2-2-2gb-40s-shared" # Cloud VPS 2 Gen 2: 2 vCPU, 2 GB RAM y 40 GB SSD
  description = "Identificador del plan de cómputo en Cherry Servers"
}

variable "server_image" {
  type        = string
  default     = "centos_stream_10_64bit"
  description = "Identificador de la imagen del sistema operativo en Cherry Servers; CentOS Stream 10 por defecto"
}

variable "ssh_public_key" {
  type        = string
  default     = ""
  description = "Tu clave pública SSH Ed25519 para acceder de forma segura sin contraseña"
}

variable "ssh_key_id" {
  type        = string
  default     = ""
  description = "Identificador de una clave SSH ya registrada en Cherry Servers para reutilizarla sin recrearla"
}

variable "server_name" {
  type        = string
  default     = "0.luanti.linenes.tld"
  description = "FQDN estructurado del servidor con formato nodo.servicio.entorno.tld"
}

variable "spot_instance" {
  type        = bool
  default     = false
  description = "Desplegar como instancia Spot con descuento en precio por hora"
}

variable "server_port" {
  type        = number
  default     = 30000
  description = "Puerto de red UDP en el que escuchará el servidor de Luanti"
}

variable "enable_bootstrap" {
  type        = bool
  default     = true
  description = "Ejecutar el script de arranque automáticamente al iniciar; usa false para laboratorios manuales paso a paso"
}
