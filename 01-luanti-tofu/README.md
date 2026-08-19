# Despliega tu propio servidor de Luanti con Infraestructura como Código (OpenTofu) en CentOS Stream 10

> **Laboratorio 01 — Servidor Dedicado de Luanti (FOSS Voxel Sandbox)**
> * **Versión del tutorial:** `v1.0.0`
> * **Fecha:** `2026-08-18`
> * **Rama de Git:** [`01-luanti-tofu`](https://gitlab.com/renich/cherry-servers/-/tree/01-luanti-tofu)
> * **Tipo de instancia:** Cloud VPS (2 vCPU / 4 GB RAM)
> * **Costo por hora:** ~$0.015 USD / hora
> * **Tiempo promedio de laboratorio:** 2 horas
> * **Gasto estimado total:** ~$0.03 USD (de tus $20 USD de crédito)

---

Dejen de levantar servidores entrando a paneles web a dar clics o lidiando con binarios propietarios obsoletos. En la ingeniería moderna de infraestructura, los servidores son **código declarativo**: defines exactamente qué quieres, ejecutas un comando, la infraestructura se levanta sola en la nube, y cuando terminas de jugar con tu comunidad, la destruyes en 5 segundos para no pagar ni un solo centavo de más.

En este primer tutorial práctico de la serie, usaremos **OpenTofu** (el estándar abierto y comunitario de Infraestructura como Código) para aprovisionar un servidor en la nube con **CentOS Stream 10**, compilar y configurar de forma automatizada un servidor dedicado de **Luanti** (el legendario motor sandbox voxel 100% libre, antes conocido como *Minetest*), configurar el firewall y gestionarlo bajo **Systemd** con aislamiento de seguridad, respetando el estándar **FHS 3.0** (`/srv/luanti`) y con **SELinux en modo Enforcing**.

---

## 1. Prerrequisitos e Instalación de OpenTofu

Para este laboratorio necesitas:
1. Tu cuenta activa con los **$20 USD de crédito** en Cherry Servers (usa el enlace fijado de la comunidad en `r/LinuxEnEspanol`).
2. Tu API Token y Project ID de Cherry Servers (generados desde el panel de control).
3. Tu clave pública SSH (`~/.ssh/id_ed25519.pub` o `~/.ssh/id_rsa.pub`). Si no tienes una, créala con `ssh-keygen -t ed25519`.
4. Tener instalado `tofu` en tu máquina de trabajo.

### Instalación de OpenTofu (CentOS Stream 10 y Fedora)

Para mantener este tutorial directo, modular y enfocado en la práctica, nos centramos en **CentOS Stream 10** como nuestra plataforma base de servidor (aplicable de igual manera a estaciones de trabajo con **Fedora**).

Ejecuta el instalador oficial para sistemas basados en RPM:

```bash
# Descargar e instalar OpenTofu vía RPM (CentOS Stream 10 / Fedora)
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method rpm
rm -f install-opentofu.sh
```

Alternativamente, puedes registrar el repositorio RPM manualmente mediante DNF:

```bash
sudo dnf install -y yum-utils
sudo dnf config-manager --add-repo https://packages.opentofu.org/opentofu/tofu/rpm_any/rpm_any/\$basearch
sudo dnf install -y tofu
```

Verifica la instalación:

```bash
tofu version
```

> **¿Trabajas desde otra distribución o sistema operativo?**
> Para no saturar el post con 10 gestores de paquetes distintos (APT, Pacman, Homebrew, APK, etc.), dejamos fuera Debian, Arch, Ubuntu, macOS y Windows. **Si estás usando otra distro, déjalo en los comentarios** y te pasamos el comando exacto al instante, o consulta la [guía de instalación oficial de OpenTofu](https://opentofu.org/docs/intro/install/).

---

## 2. Estructura del Proyecto

Para que el modelo mental sea completamente claro y sin "cajas negras", usamos una **arquitectura plana y lineal** (sin módulos anidados complejos).

Crea un directorio local para organizar los manifiestos:

```bash
mkdir -p luanti-lab/scripts
cd luanti-lab
```

La estructura de archivos debe quedar así:

```text
luanti-lab/
├── provider.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars
└── scripts/
    └── bootstrap.sh
```

### Configuración del Proveedor (`provider.tf`)

```hcl
# =============================================================================
# 1. Configuración del Proveedor (Cherry Servers)
# =============================================================================
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    cherryservers = {
      source  = "cherryservers/cherryservers"
      version = "~> 1.5.3"
    }
  }
}

provider "cherryservers" {
  api_token = var.cherry_auth_token
}
```

### Definición de Variables (`variables.tf`)

```hcl
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
  description = "El ID numérico del proyecto en Cherry Servers"
}

variable "region" {
  type        = string
  default     = "EU-East-1" # Lituania (máxima disponibilidad de Spot y menor costo)
  description = "Ubicación geográfica del centro de datos"
}

variable "server_plan" {
  type        = string
  default     = "Cloud-VPS-2" # 2 vCPU / 4 GB RAM (ideal para Luanti con 25 jugadores)
  description = "Plan de tamaño del servidor virtual"
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
```

> **¿Por qué usamos la convención `0.luanti.linenes.tld`?**
> En ingeniería de confiabilidad de sitios (SRE) e infraestructura profesional, **no usamos nombres de mascotas o arbitrarios** (*"zeus"*, *"thor"*, *"miserver"*). Usamos un esquema jerárquico estructurado tipo FQDN (*Fully Qualified Domain Name*):
> - `0`: Índice numérico del nodo dentro de una flota basada en índice cero (`0`, `1`, `2`...).
> - `luanti`: Servicio o carga de trabajo principal.
> - `linenes`: Identificador del entorno o comunidad (`LinuxEnEspanol`).
> - `tld`: *Top-Level Domain* (Dominio de Nivel Superior).
>
> **¿Qué es un TLD (*Top-Level Domain*)?**
> Es el nivel más alto en la jerarquía del Sistema de Nombres de Dominio (DNS) de Internet, ubicado inmediatamente después del punto raíz (ej. `.com`, `.org`, `.mx`, o dominios privados de laboratorio como `.internal`, `.lan`, `.local`). En guías técnicas y estándares (siguiendo las recomendaciones de los RFC 2606 y RFC 6761), usamos `.tld` como un marcador de posición estándar para indicar al estudiante que allí colocará su dominio propio o zona raíz local.

### Aprovisionamiento y Automatización (`main.tf`)

```hcl
# =============================================================================
# 3. Recursos de Infraestructura (Flujo Lineal y Plano)
# =============================================================================

# Paso 1: Registramos tu clave pública SSH en el proyecto de Cherry Servers
resource "cherryservers_ssh_key" "deployer" {
  name       = "luanti-deployer-key"
  public_key = var.ssh_public_key
}

# Paso 2: Aprovisionamos la máquina virtual en la nube con CentOS Stream 10
resource "cherryservers_server" "luanti_node" {
  project_id  = var.project_id
  region      = var.region
  plan        = var.server_plan
  image       = "centos-stream-10"
  hostname    = "luanti-dedicated"
  ssh_key_ids = [cherryservers_ssh_key.deployer.id]

  # Inyectamos el script de arranque codificado en Base64 (requerido por Cherry Servers)
  user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh", {
    SERVER_NAME = var.server_name
    SERVER_PORT = 30000
  }))

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "LinuxEnEspanol"
    Game        = "Luanti"
  }
}
```

### Salidas del Despliegue (`outputs.tf`)

```hcl
# =============================================================================
# 4. Salidas del Despliegue (Outputs)
# =============================================================================

locals {
  primary_ip = one([for ip in cherryservers_server.luanti_node.ip_addresses : ip.address if ip.type == "primary-ip"])
}

output "server_ip" {
  description = "Dirección IP pública del servidor"
  value       = local.primary_ip
}

output "connection_string" {
  description = "Dirección para conectar directamente en el cliente de Luanti"
  value       = "${local.primary_ip}:30000"
}

output "ssh_command" {
  description = "Comando directo para acceder a la terminal del servidor por SSH"
  value       = "ssh root@${local.primary_ip}"
}
```

### Script de Aprovisionamiento (`scripts/bootstrap.sh`)

Este script se ejecuta automáticamente al iniciar la máquina. Aplica el estándar **FHS 3.0** alojando el servicio en `/srv/luanti` y configurando un usuario de sistema sin acceso a shell (`/sbin/nologin`):

```bash
#!/usr/bin/bash
set -euo pipefail

# Registro de ejecución en logs y consola
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue de Luanti (Motor Voxel FOSS) en CentOS Stream 10..."

# 1. Habilitar repositorios EPEL/CRB e instalar dependencias
dnf install -y epel-release dnf-plugins-core
/usr/bin/crb enable || true
dnf install -y \
    firewalld \
    git \
    cmake \
    gcc-c++ \
    sqlite-devel \
    zlib-devel \
    jsoncpp-devel \
    libzstd-devel \
    curl \
    tar \
    jq

# 2. Compilar el servidor dedicado headless de Luanti (64-bit nativo)
BUILD_DIR="/usr/local/src/luanti-build"
mkdir -p "$${BUILD_DIR}"
cd "$${BUILD_DIR}"

if [[ ! -d luanti ]]; then
    git clone --depth 1 https://github.com/luanti-org/luanti.git
fi

cd luanti

if [[ ! -d games/minetest_game ]]; then
    git clone --depth 1 https://github.com/minetest/minetest_game.git games/minetest_game
fi

cmake -B build \
    -DBUILD_SERVER=TRUE \
    -DBUILD_CLIENT=FALSE \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local

cmake --build build -j"$(nproc)"
cmake --install build

# 3. Instalar juego base (minetest_game) para el servidor
mkdir -p /usr/local/share/luanti/games
cp -r games/minetest_game /usr/local/share/luanti/games/

# 4. Crear usuario de sistema y estructura FHS 3.0 en /srv/luanti
useradd -r -s /sbin/nologin -d /srv/luanti -m -c "Luanti Dedicated Service" luanti || true
mkdir -p /srv/luanti/{config,worlds,games,logs}
cp -r games/minetest_game /srv/luanti/games/

# 4. Configurar el servidor en /srv/luanti/config/luanti.conf
cat <<CONFIG > /srv/luanti/config/luanti.conf
name = LinuxEnEspanol-Lab
server_name = ${SERVER_NAME}
server_description = Servidor 100% FOSS en CentOS Stream 10 desplegado con OpenTofu
server_address = 0.0.0.0
port = ${SERVER_PORT}
default_game = minetest_game
enable_damage = true
creative_mode = false
server_announce = false
max_users = 25
motd = ¡Bienvenido al servidor comunitario de r/LinuxEnEspanol! 100% FOSS en CentOS Stream 10.
CONFIG

chown -R luanti:luanti /srv/luanti
chmod 750 /srv/luanti
chmod 640 /srv/luanti/config/luanti.conf

# 5. Crear la unidad de servicio Systemd endurecida (Hardened)
cat <<SERVICE > /etc/systemd/system/luanti.service
[Unit]
Description=Luanti Dedicated Voxel Game Server
After=network.target

[Service]
Type=simple
User=luanti
Group=luanti
WorkingDirectory=/srv/luanti
ExecStart=/usr/local/bin/luantiserver --config /srv/luanti/config/luanti.conf --world /srv/luanti/worlds/midgard --gameid minetest_game
Restart=on-failure
RestartSec=5
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/srv/luanti
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

# 6. Contextos de SELinux y arranque del servicio
restorecon -Rv /srv/luanti /usr/local/bin/luantiserver || true
systemctl daemon-reload
systemctl enable --now luanti.service

# 7. Configurar Firewall para el puerto UDP de Luanti (30000)
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=${SERVER_PORT}/udp
firewall-cmd --reload

echo "[+] Servidor de Luanti desplegado con éxito en /srv/luanti y escuchando en UDP ${SERVER_PORT}."
```

### Configuración de Credenciales (`terraform.tfvars`)

Crea tu archivo `terraform.tfvars` con tus credenciales reales:

```hcl
cherry_auth_token = "TU_API_TOKEN_AQUI"
project_id        = 123456
ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tu_correo@dominio.com"
server_name       = "0.luanti.linenes.tld"
```

---

## 3. Despliegue en un solo comando

1. Inicializa el proveedor de Cherry Servers:
   ```bash
   tofu init
   ```

2. Verifica el plan de ejecución:
   ```bash
   tofu plan
   ```

3. Aplica los cambios para levantar el servidor:
   ```bash
   tofu apply -auto-approve
   ```

OpenTofu se comunicará con la API de Cherry Servers, creará la instancia con CentOS Stream 10, inyectará tu llave SSH y ejecutará la compilación y arranque automático.

Al finalizar, la terminal te entregará los outputs:

```text
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

connection_string = "84.32.188.42:30000"
server_ip = "84.32.188.42"
ssh_command = "ssh root@84.32.188.42"
```

---

## 4. Verificación y Conexión

El servidor tardará entre 2 y 3 minutos en compilar el binario headless nativo e inicializar el mapa voxel. Puedes conectarte por SSH para monitorear el servicio en tiempo real:

```bash
ssh root@<TU_IP>
journalctl -u luanti.service -f
```

Cuando veas en los logs `ACTION[Server]: Listening on 0.0.0.0:30000`:
1. Abre tu cliente de **Luanti** (disponible en Flathub, repositorios de Linux, Android, Windows y macOS).
2. Selecciona la pestaña **Join Game** (Unirse a partida).
3. Introduce la IP de tu servidor y el puerto `30000`.
4. Elige un nombre de usuario y contraseña para tu cuenta en el servidor ¡y comienza a construir!

---

## 5. El paso OBLIGATORIO: Destrucción de la Infraestructura

En la nube no dejamos servidores encendidos si no los estamos usando. Cuando termines tu sesión de juego o tus pruebas de laboratorio, destruye todo ejecutando:

```bash
tofu destroy -auto-approve
```

Este comando ordena a la API eliminar la instancia por completo. Tu saldo de $20 USD permanecerá prácticamente intacto (~$19.97 USD) para los siguientes 9 laboratorios de la serie.
