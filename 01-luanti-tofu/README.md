# Cómo desplegar tu propio servidor de Luanti en CentOS Stream 10 con OpenTofu y COPR

> **Cómo 01 — Servidor Dedicado de Luanti (Sandbox Voxel FOSS)**
>
> * **Versión:** `v1.0.0`
> * **Fecha:** `2026-08-18`
> * **Rama de Git:** [`01-luanti-tofu`](https://gitlab.com/renich/cherry-servers/-/tree/01-luanti-tofu)
> * **Tipo de instancia:** Cloud VPS 2 (Gen 2: 2 vCPU/2 GB RAM/40GB SSD)
> * **Costo por hora:** ~$0.033 EUR/hora (~$0.035 USD/hora)
> * **Tiempo promedio:** 1 hora
> * **Gasto estimado total:** ~$0.03 USD

---

¡Hola! 👋

Te doy una calurosa bienvenida a esta nueva **serie práctica de «Cómos» de infraestructura y administración de sistemas en Linux**, creada con entusiasmo para toda la **comunidad de software libre de Latinoamérica** y para ti, que disfrutas aprender cómo funcionan los sistemas a bajo nivel.

A lo largo de esta secuencia de 10 Cómos prácticos y autosuficientes, explorarás desde servidores de juegos y proxies inversos con contenedores, hasta almacenamiento distribuido S3, clústeres de Kubernetes con K3s e inferencia local de modelos de Inteligencia Artificial.

En este **primer Cómo**, aprenderás a poner en marcha tu propio servidor dedicado de **Luanti** (el motor sandbox de bloques 100% libre, antes conocido como *Minetest*):

1. **Aprovisionarás un servidor base en la nube** con **CentOS Stream 10** usando **OpenTofu**.
1. **Aprenderás qué es Fedora COPR** y cómo integrar repositorios comunitarios de RPM para instalar paquetes en entornos empresariales de forma limpia y estándar.
1. **Configurarás el servicio manualmente vía SSH:** estructura de directorios bajo el estándar **FHS 3.0** (`/var/lib/minetest`), usuario de sistema sin shell de login, unidad de servicio parametrizada en **Systemd** (`minetest@default.service`), **SELinux en modo Enforcing** y reglas de **Firewalld**.
1. **Automatizarás todo el proceso** en un script declarativo (`scripts/bootstrap.bash`) para que puedas reproducir o destruir tu infraestructura en menos de 30 segundos con un solo comando.

---

## 1. Prerrequisitos y Preparación

Para realizar este Cómo necesitas:

1. Una cuenta activa en Cherry Servers.
1. Tu **API Token** y **Project ID** de Cherry Servers (obtenidos desde el panel de control en *API Keys* y en la vista de tu proyecto).
1. Tu clave pública SSH (`~/.ssh/id_ed25519.pub`). Si aún no tienes una:

   ```bash
   ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"
   ```

1. Tener instalado **OpenTofu** (versión `>= 1.8.0`) en tu estación de trabajo (asumiendo **Fedora 44** o **CentOS Stream 10** como estación secundaria).

### Instalación de OpenTofu en Fedora/CentOS Stream

OpenTofu se encuentra disponible como paquete RPM nativo en los repositorios oficiales de **Fedora** y en **EPEL 10** para CentOS Stream:

```bash
# En Fedora Linux (repositorio oficial):
sudo dnf -y install opentofu

# En CentOS Stream 10 / RHEL 10 (repositorio EPEL 10):
sudo dnf -y install epel-release
sudo dnf -y install opentofu

# Verificar versión instalada (versión >= 1.8.0)
tofu version
```

### Instalación del Cliente en tu Estación de Trabajo (Fedora Linux)

Para conectarte al servidor y jugar desde tu computadora (asumiendo **Fedora Linux** como estación de trabajo):

```bash
sudo dnf -y install minetest
```

> **Nota sobre el nombre del paquete:** Aunque el proyecto cambió de nombre oficialmente a **Luanti** a partir de la versión 5.10+, en los repositorios oficiales de Fedora el paquete RPM de la aplicación de escritorio conserva el nombre histórico `minetest` (y el servidor `minetest-server`). Al instalar `minetest`, tu sistema instalará el lanzador de escritorio con la interfaz gráfica moderna de Luanti.

---

## 2. Aprovisionamiento Base con OpenTofu

Clona el repositorio oficial de la serie y cámbiate a la rama del Cómo:

```bash
git clone https://gitlab.com/renich/cherry-servers.git
cd cherry-servers
git checkout 01-luanti-tofu
cd 01-luanti-tofu/tofu
```

### Estructura de los Manifiestos de OpenTofu

Seguimos una arquitectura **plana y lineal** (sin módulos anidados opacos):

* `provider.tf`: Declara el proveedor oficial de Cherry Servers (`cherryservers/cherryservers`).
* `variables.tf`: Define los parámetros del servidor con valores por defecto óptimos.
* `main.tf`: Declara la llave SSH y el recurso de cómputo Cloud VPS.
* `outputs.tf`: Expone la IP pública y el comando de conexión SSH.
* `terraform.tfvars.example`: Plantilla de variables para tus credenciales locales.

> **¿Por qué se usa el nombre de host `0.luanti.linenes.tld`?**
>
> En ingeniería de confiabilidad de sitios (SRE), **no se usan nombres de mascotas** (*"zeus"*, *"servidor1"*). Se usa un esquema jerárquico FQDN (*Fully Qualified Domain Name*):
>
> * `0`: Índice de nodo dentro de una flota en base cero (`0`, `1`, `2`...).
> * `luanti`: Servicio o carga de trabajo principal.
> * `linenes`: Identificador del entorno o comunidad (*Linux en Español*).
> * `tld`: *Top-Level Domain* (Dominio de Nivel Superior, como `.internal`, `.lan` o tu dominio propio). Se usa `.tld` como marcador de posición pedagógico estándar según los RFC 2606 y RFC 6761.

### Configurar Variables Locales

Copia la plantilla de ejemplo y edítala con tus datos:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tu editor preferido:

```hcl
cherry_auth_token = "TU_API_TOKEN_AQUI"
project_id        = 123456
ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tu_correo@ejemplo.com"
server_name       = "0.luanti.linenes.tld"
```

*(Nota de seguridad: el archivo `terraform.tfvars` está protegido en `.gitignore` para que tus claves privadas nunca se suban a ningún repositorio).*

### Desplegar la Instancia Base

Inicializa OpenTofu y aplica el manifiesto:

```bash
tofu init
tofu plan
tofu apply
```

En aproximadamente 2 minutos, OpenTofu terminará de aprovisionar el servidor en Lituania (`LT-Siauliai`) y te devolverá la dirección IP:

```text
Outputs:

connection_string = "84.32.109.243:30000"
server_ip = "84.32.109.243"
ssh_command = "ssh root@84.32.109.243"
```

---

## 3. Construcción y Configuración Manual vía SSH (El Núcleo del Aprendizaje)

Conéctate por SSH a tu nuevo servidor:

```bash
ssh root@84.32.109.243
```

---

### Paso A: Fundamentos de Fedora COPR y propósito de uso

**COPR** (*Cool Other Package Repository*) es el sistema oficial de construcción y distribución de paquetes comunitarios del Proyecto Fedora. Permite a mantenedores y desarrolladores empaquetar software siguiendo las directrices oficiales de empaquetamiento de RPM (`rpmbuild`, `mock`) y distribuirlo automáticamente para Fedora, EPEL y CentOS/RHEL.

> **Crédito al Mantenedor:**
>
> Para CentOS Stream 10/EPEL 10, utilizamos el repositorio COPR empaquetado y mantenido por **David Herrera (`dherrera`)**:
> [`copr.fedorainfracloud.org/coprs/dherrera/minetest`](https://copr.fedorainfracloud.org/coprs/dherrera/minetest/)
>
> *(Nota: En Fedora 44, el paquete `minetest-server` ya viene incluido en los repositorios oficiales base sin necesidad de habilitar COPR).*

---

### Paso B: Habilitar Repositorios e Instalar el Paquete RPM

Habilita **EPEL 10**, **CRB** (*CodeReady Linux Builder*) y el repositorio COPR de `dherrera/minetest`:

```bash
# 1. Habilitar EPEL 10 y herramientas DNF
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable

# 2. Habilitar el repositorio COPR
dnf -y copr enable dherrera/minetest

# 3. Instalar el paquete RPM del servidor dedicado
dnf -y install minetest-server firewalld jq curl
```

En menos de 5 segundos, DNF descargará e instalará el binario compilado `/usr/bin/minetestserver`, el juego base oficial `minetest_game`, la unidad de servicio `minetest@.service` y creará automáticamente el usuario de sistema `minetest`.

---

### Paso C: Estructura de Datos y Permisos (FHS 3.0)

El paquete RPM organiza los datos en `/var/lib/minetest`. Asegúrate de que el usuario de sistema `minetest` tenga la propiedad y los permisos adecuados:

```bash
# Crear estructura de datos para la instancia por defecto
mkdir -p /var/lib/minetest/{default,.minetest/games}

# Asignar propiedad al usuario dedicado del sistema
chown -R minetest:minetest /var/lib/minetest /etc/minetest
chmod 750 /var/lib/minetest
```

---

### Paso D: Configuración del Servidor (`/etc/minetest/default.conf`)

Crea o edita el archivo de configuración del servidor en `/etc/minetest/default.conf`:

```bash
cat <<'EOF' > /etc/minetest/default.conf
name = LinuxEnEspanol-Lab
server_name = 0.luanti.linenes.tld
server_description = Servidor 100% FOSS en CentOS Stream 10 desplegado con OpenTofu y COPR
server_address = 0.0.0.0
port = 30000
default_game = minetest_game
enable_damage = true
creative_mode = false
server_announce = false
max_users = 25
motd = ¡Bienvenido al servidor comunitario de Luanti! Empaquetado en COPR y desplegado con OpenTofu.
EOF

# Permisos seguros para el archivo de configuración
chown minetest:minetest /etc/minetest/default.conf
chmod 640 /etc/minetest/default.conf
```

---

### Paso E: Gestión del Servicio en Systemd (`minetest@.service`)

El paquete RPM incluye una **unidad de servicio Systemd con plantilla** (`minetest@.service`). Esto permite correr múltiples instancias del servidor de forma independiente simplemente cambiando el nombre de la instancia (por ejemplo, `minetest@default.service` o `minetest@pvp.service`):

```bash
# Iniciar y habilitar la instancia por defecto
systemctl daemon-reload
systemctl enable --now minetest@default.service
```

Inspecciona el estado del servicio:

```bash
systemctl status minetest@default.service
```

Verás una salida activa similar a:

```text
● minetest@default.service - Minetest multiplayer server w/ default.conf server config
     Loaded: loaded (/usr/lib/systemd/system/minetest@.service; enabled)
     Active: active (running)
   Main PID: 9647 (minetestserver)
     CGroup: /system.slice/system-minetest.slice/minetest@default.service
             └─9647 /usr/bin/minetestserver --config /etc/minetest/default.conf --port 30000 ...

ACTION[Main]: Server for gameid="minetest" listening on [::]:30000.
```

---

### Paso F: SELinux en Modo Enforcing y Reglas de Firewall

CentOS Stream 10 opera con **SELinux en modo Enforcing**. Aplica los contextos correspondientes y abre el puerto en `firewalld`:

```bash
# Restaurar contextos de SELinux
restorecon -Rv /var/lib/minetest /etc/minetest /usr/bin/minetestserver

# Configurar el Firewall para el puerto UDP 30000
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=30000/udp
firewall-cmd --reload
```

Verifica que el socket de red UDP esté escuchando:

```bash
ss -ulnp | grep 30000
```

---

### Paso G: Conexión desde el Cliente de Juego

1. Abre tu cliente de **Luanti** (o *Minetest*) en tu computadora y selecciona la pestaña **Unirse a partida** (*Join Game*).
1. En el campo **Dirección** (*Address*), ingresa la IP pública de tu servidor (ej. `84.32.109.243`) y en **Puerto** (*Port*) el `30000`.
1. En el campo **Nombre** (*Name*), escribe el nombre de usuario con el que jugarás (ej. `renich`).
1. Haz clic en el botón **Register** (*Registrar*).
1. El cliente abrirá una ventana emergente solicitándote **definir y confirmar tu contraseña** para este servidor.
1. Una vez confirmada, el cliente descargará los bloques y recursos del servidor y entrarás directamente a jugar en tu propio mundo voxel.

> **Nota para sesiones futuras:** En tus siguientes partidas, ya no necesitas pulsar *Register*. Simplemente escribe tu usuario, tu contraseña en el formulario principal y haz clic en **Login** (*Iniciar sesión*).

---

## 4. La Vía Automatizada (Para Producción y Despliegues Rápidos)

Ahora que conoces todos los componentes y el ciclo de vida del paquete RPM, puedes automatizar el aprovisionamiento completo usando el script [`scripts/bootstrap.bash`](file:///home/renich/Projects/cherry-servers/01-luanti-tofu/scripts/bootstrap.bash).

Al inyectar `bootstrap.bash` dentro de `user_data` en OpenTofu:

```hcl
resource "cherryservers_server" "luanti_node" {
  project_id  = var.project_id
  region      = var.region
  plan        = var.server_plan
  image       = "centos_stream_10_64bit"
  hostname    = var.server_name
  ssh_key_ids = [cherryservers_ssh_key.deployer.id]

  # Inyectamos el script de arranque codificado en Base64 (requerido por Cherry Servers)
  user_data = base64encode(templatefile("${path.module}/../scripts/bootstrap.bash", {
    SERVER_NAME = var.server_name
    SERVER_PORT = 30000
  }))

  tags = {
    Environment = "Lab"
    ManagedBy   = "OpenTofu"
    Series      = "Comos-Linux-FOSS"
    Game        = "Luanti"
  }
}
```

Cada vez que ejecutes `tofu apply`, la máquina virtual se creará, habilitará el repositorio COPR, instalará el RPM de `minetest-server` y configurará el servicio en **menos de 30 segundos**.

---

## 5. Destrucción del Servidor y Control de Costos

Para mantener la disciplina de costos en la nube:

Desde la carpeta `01-luanti-tofu/tofu`:

```bash
tofu destroy
```

Confirma escribiendo `yes` (o usa `-auto-approve`). OpenTofu eliminará la instancia y la clave SSH en Cherry Servers:

```text
Destroy complete! Resources: 2 destroyed.
```

El costo total de haber corrido este Cómo completo habrá sido de aproximadamente **~$0.02 a $0.03 USD**.

---

### Dudas y Preguntas

Deja tus dudas o comentarios abriendo un Issue en el repositorio de GitLab. ¡Nos vemos en el **Cómo 02: Reverse Proxy con Caddy y Vaultwarden en Podman**!
