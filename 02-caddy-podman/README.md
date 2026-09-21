# Cómo desplegar Vaultwarden en Podman Quadlets con Caddy y SELinux en CentOS Stream 10

> **Cómo 02 — Caddy Reverse Proxy y Vaultwarden en Podman con SELinux**
>
> * **Versión:** `v1.0.0`
> * **Fecha:** `2026-08-19`
> * **Rama de Git:** [`02-caddy-podman`](https://gitlab.com/renich/cherry-servers/-/tree/02-caddy-podman)
> * **Tipo de instancia:** Cloud VPS 1 (Gen 2: 1 vCPU/1 GB RAM/20GB SSD) o Cloud VPS 2
> * **Costo por hora:** ~$0.015 EUR/hora (~$0.016 USD/hora)
> * **Tiempo promedio:** 1-2 horas
> * **Gasto estimado total:** ~$0.03 USD

---

¡Hola! 👋

Te doy la bienvenida al **segundo Cómo** de nuestra serie de infraestructura y administración de sistemas en Linux para la comunidad de software libre.

En entornos reales de producción y laboratorios hogareños (*homelabs*), exponer contenedores abriendo puertos arbitrarios directamente en internet (como `:8080`, `:3000` o `:9000`) es una mala práctica de seguridad y arquitectura. La arquitectura estándar de la industria coloca al frente un **proxy inverso seguro** que escucha en los puertos estándar HTTP/HTTPS (`80` y `443`), gestiona la terminación TLS y enruta las peticiones basándose en nombres de dominio (*Virtual Hosting* con SNI/FQDN) hacia servicios internos aislados.

En este laboratorio aprenderás a desplegar **Vaultwarden** (la implementación ligera, eficiente y 100% libre escrita en Rust del backend de Bitwarden) gestionada por **Podman Quadlets** en **Systemd**, protegida por **SELinux en modo Enforcing** y publicada a través del servidor web **Caddy** instalado como paquete RPM nativo.

Fieles a nuestra filosofía **«Manual Primero, Automatización Después»**, primero realizaremos todo el despliegue a mano en la terminal mediante SSH, entendiendo cada directiva, contexto de SELinux y regla de firewall. Posteriormente, empaquetaremos la solución completa en un despliegue declarativo e instantáneo con **OpenTofu**.

---

## 1. Prerrequisitos del Laboratorio

1. Un servidor con **CentOS Stream 10** en la nube (o máquina virtual local) con acceso SSH como `root` mediante clave pública Ed25519 (`~/.ssh/id_ed25519.pub`). Si aún no tienes un par de llaves:

   ```bash
   ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"
   ```

1. Clientes y herramientas en tu estación de trabajo (**Fedora Linux**):

   * Navegador web moderno (Firefox, Chromium) o la extensión oficial de Bitwarden.
   * Utilidades de red y OpenTofu instaladas:

   ```bash
   sudo dnf -y install curl jq opentofu
   ```

1. **Resolución de nombres (DNS o `/etc/hosts`):**
   Para este laboratorio utilizaremos por defecto el dominio pedagógico `secretos.linenes.tld`. Al no contar con un registro DNS público global para `.tld`, apuntaremos el nombre a la IP de nuestro servidor mediante el archivo local `/etc/hosts` en tu estación de trabajo. Si cuentas con un dominio público propio (ej. `secretos.tudominio.com`), podrás configurarlo directamente mediante un registro DNS tipo `A`.

---

## 2. Construcción y Configuración Manual vía SSH (El Núcleo del Aprendizaje)

Conéctate por SSH a tu servidor:

```bash
ssh root@<IP_DEL_SERVIDOR>
```

### Paso A: Arquitectura de la Solución (Caddy RPM, Podman Quadlets y FQDN)

Nuestra arquitectura divide responsabilidades de forma limpia y robusta:

1. **Caddy en el Host (RPM):** Se ejecuta directamente en el sistema operativo base. Tiene acceso directo a los puertos privilegiados `80/tcp` y `443/tcp`, administra los certificados TLS (públicos vía Let's Encrypt o auto-firmados internos con su propia CA) y reenvía el tráfico internamente.
1. **Vaultwarden en Podman Quadlet:** En lugar de depender de un demonio monolítico en segundo plano (como Docker), Podman Quadlet traduce archivos de definición declarativos (`.container`) en unidades nativas de **Systemd**. El contenedor se inicia, monitorea y reinicia como cualquier otro servicio del sistema operativo, registrando su salida directamente en `journald`.
1. **Aislamiento en Loopback:** El contenedor de Vaultwarden expone su puerto interno únicamente en la interfaz de bucle invertido (`127.0.0.1:8080`). Nunca se expone a interfaces públicas (`0.0.0.0`), garantizando que nadie pueda evadir el proxy de Caddy.
1. **Seguridad con SELinux:** Operamos con SELinux en modo **Enforcing**. Veremos cómo habilitar el booleano `httpd_can_network_connect` para permitir que Caddy se comunique con el puerto local, y cómo etiquetar los volúmenes del contenedor con `:Z` para que los procesos confinados puedan persistir datos en `/srv/vaultwarden/data`.

### Paso B: Habilitar Repositorios e Instalar Paquetes RPM

Habilita **EPEL 10**, **CRB** y el repositorio oficial de Caddy en COPR (`@caddy/caddy`):

```bash
# 1. Habilitar EPEL 10 y herramientas auxiliares
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable

# 2. Habilitar el repositorio oficial de Caddy
dnf -y copr enable @caddy/caddy

# 3. Instalar Caddy, Podman, Firewalld y herramientas de diagnóstico
dnf -y install caddy podman firewalld curl jq
```

> **¿Por qué el repositorio COPR `@caddy/caddy`?**
>
> El equipo oficial de desarrollo de Caddy mantiene este repositorio en Fedora COPR para proveer compilaciones actualizadas y optimizadas de Caddy v2 para el ecosistema RHEL, CentOS Stream y Fedora, incluyendo integración completa con Systemd y políticas base de SELinux.

### Paso C: Estructura de Datos y Permisos bajo FHS 3.0

Bajo el estándar **FHS 3.0** (*Filesystem Hierarchy Standard*), los datos de servicios específicos del sitio deben residir en `/srv/<servicio>`. Crearemos el directorio para la base de datos SQLite y adjuntos de Vaultwarden:

```bash
# Crear estructura de datos persistente
mkdir -p /srv/vaultwarden/data

# Configurar permisos de lectura y escritura seguros
chmod 750 /srv/vaultwarden /srv/vaultwarden/data
```

### Paso D: Declarar el Contenedor con Podman Quadlet

**Quadlet** es un generador de Systemd introducido en las versiones modernas de Podman. Permite declarar contenedores mediante una sintaxis idéntica a los archivos `.ini` de Systemd.

Crea el archivo `/etc/containers/systemd/vaultwarden.container`:

```bash
mkdir -p /etc/containers/systemd

cat << 'EOF' > /etc/containers/systemd/vaultwarden.container
[Unit]
Description=Vaultwarden Password Manager (Podman Quadlet)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network-online.target firewalld.service

[Container]
Image=docker.io/vaultwarden/server:latest
ContainerName=vaultwarden
PublishPort=127.0.0.1:8080:80
Volume=/srv/vaultwarden/data:/data:Z
Environment=SIGNUPS_ALLOWED=true
Environment=WEBSOCKET_ENABLED=true
AutoUpdate=registry

[Install]
WantedBy=multi-user.target default.target
EOF

chmod 644 /etc/containers/systemd/vaultwarden.container
```

**Análisis de las directivas clave del Quadlet:**

* `PublishPort=127.0.0.1:8080:80`: Mapea el puerto `80` del contenedor al puerto `8080` de la máquina anfitriona **exclusivamente en `127.0.0.1`**. El tráfico externo no tiene acceso directo.
* `Volume=/srv/vaultwarden/data:/data:Z`: Monta el almacenamiento persistente. La bandera `:Z` le indica a Podman que aplique una etiqueta privada de SELinux (`container_file_t`) con una categoría MCS exclusiva para este contenedor.
* `AutoUpdate=registry`: Permite que `podman-auto-update.timer` mantenga actualizado el contenedor automáticamente cuando se publiquen nuevas versiones en el registro upstream.

Ahora recarga el generador de Systemd e inicia el servicio:

```bash
# Recargar Systemd para que el generador Quadlet cree la unidad dinámica
systemctl daemon-reload

# Iniciar el servicio generado por Quadlet
systemctl start vaultwarden.service
```

> **Nota técnica sobre unidades generadas por Quadlet:**
>
> Los archivos `.container` de Quadlet que incluyen la sección `[Install]` son habilitados automáticamente por el generador de Systemd en `/run/systemd/generator/` tras cada `systemctl daemon-reload` o arranque del sistema. Por ello, no se requiere ejecutar `systemctl enable` (el cual emitiría una advertencia de que la unidad es generada/transitoria); basta con invocar `systemctl start vaultwarden.service`.

Verifica el estado del servicio:

```bash
systemctl status vaultwarden.service
```

Observa cómo Systemd gestiona el contenedor como un servicio nativo de primera clase:

```text
● vaultwarden.service - Vaultwarden Password Manager (Podman Quadlet)
     Loaded: loaded (/etc/containers/systemd/vaultwarden.container; generated)
     Active: active (running)
...
```

Puedes comprobar que el puerto responde internamente en localhost:

```bash
curl -I http://127.0.0.1:8080/
```

Recibirás un encabezado HTTP `200 OK` generado por el servidor Rust de Vaultwarden.

### Paso E: Configuración del Proxy Inverso en Caddy (`/etc/caddy/Caddyfile`)

Caddy simplifica radicalmente la administración de servidores web. Genera la configuración en `/etc/caddy/Caddyfile` apuntando a tu dominio virtual:

```bash
# Crear directorio de registros
mkdir -p /var/log/caddy

cat << 'EOF' > /etc/caddy/Caddyfile
{
    admin off
}

secretos.linenes.tld {
    # Habilitar TLS interno auto-firmado para dominios locales o de laboratorio (.tld)
    tls internal

    # Proxy inverso al socket local de Vaultwarden
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    log {
        output file /var/log/caddy/vaultwarden.access.log
        format json
    }
}
EOF

chown -R caddy:caddy /etc/caddy /var/log/caddy
chmod 640 /etc/caddy/Caddyfile
restorecon -Rv /var/log/caddy /etc/caddy
```

> **Diferencia entre dominios de laboratorio y dominios públicos:**
>
> * **Dominio de laboratorio (`.tld`, `.lan`, `.local`, `.internal`):** Usamos la directiva `tls internal`. Caddy genera su propia Autoridad Certificadora (CA) local y firma un certificado TLS válido para el nombre de host sin intentar contactar a Let's Encrypt (lo que fallaría, ya que `.tld` no es un TLD público enraizado en el IANA).
> * **Dominio público en internet (ej. `secretos.tudominio.com`):** Basta con **eliminar la línea `tls internal`**. Caddy automáticamente solicitará y renovará un certificado público TLS gratuito mediante Let's Encrypt o ZeroSSL mediante el protocolo ACME.

### Paso F: SELinux a Fondo (Modo Enforcing, AVCs y Firewall)

CentOS Stream 10 opera con **SELinux en modo Enforcing**. Si intentas iniciar un proxy inverso hacia un backend local sin verificar las políticas de SELinux, te toparás con un error **502 Bad Gateway**.

#### 1. Diagnóstico del bloqueo de SELinux (El por qué)

El binario de Caddy corre bajo el dominio de SELinux `httpd_t`. Por razones de seguridad, la política predeterminada de SELinux en sistemas basados en Red Hat **prohíbe** que un servidor web inicie conexiones TCP salientes hacia otros puertos de red (`name_connect`).

Si Caddy intentara conectarse a `127.0.0.1:8080` sin autorización, el kernel registraría una denegación AVC en los registros de auditoría similar a esta:

```text
type=AVC msg=audit(1724021234.567:123): avc:  denied  { name_connect } for  pid=12345 comm="caddy" dest=8080 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:http_cache_port_t:s0 tclass=tcp_socket permissive=0
```

#### 2. Solución canónica mediante booleanos de SELinux

En lugar de relajar SELinux o desactivarlo (lo cual está terminantemente desaconsejado en entornos de producción), verificamos y habilitamos el booleano oficial del sistema diseñado para servidores web y proxies inversos:

```bash
# Permitir permanentemente (-P) que el servidor web se conecte por red a backends locales
setsebool -P httpd_can_network_connect 1
```

*(Nota: Aunque el scriptlet RPM de Caddy en COPR activa este booleano durante su instalación, conocerlo y verificarlo con `getsebool httpd_can_network_connect` es una habilidad fundamental de SRE para diagnosticar fallas en cualquier proxy como Nginx, Apache o Envoy).*

#### 3. Etiquetado de volúmenes de contenedor (`:Z`)

El contenedor de Vaultwarden se ejecuta bajo el tipo de contexto `container_t`. Por defecto, los directorios creados en `/srv/` poseen contextos genéricos como `var_t` o `default_t`. Si el contenedor intentara escribir su base de datos SQLite en `/srv/vaultwarden/data`, el kernel denegaría el acceso.

Al haber especificado `Volume=/srv/vaultwarden/data:/data:Z` en el archivo Quadlet:

* `:Z` indica a Podman que etiquete automáticamente el directorio con el contexto `container_file_t`.
* Asigna categorías MCS (*Multi-Category Security*) aleatorias y exclusivas (por ejemplo, `s0:c123,c456`) que aíslan los archivos de esta instancia frente a cualquier otro contenedor en el sistema.

Verifiquemos el contexto resultante en el sistema de archivos:

```bash
ls -Zd /srv/vaultwarden/data
```

Verás una salida con el tipo correcto `container_file_t`:

```text
system_u:object_r:container_file_t:s0 /srv/vaultwarden/data
```

#### 4. Configurar el Firewall del Sistema

Habilita los servicios estándar de tráfico web en `firewalld`:

```bash
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

Inicia y habilita el servicio de Caddy:

```bash
systemctl daemon-reload
systemctl enable --now caddy.service
```

Comprueba los sockets de red activos en el servidor:

```bash
ss -tlpn | grep -E ':(80|443)'
```

> **¿Por qué el puerto 8080 no aparece en `ss -tlpn`?**
>
> En versiones modernas de Podman sobre CentOS Stream y Fedora, la pila de red predeterminada es **Netavark**. En lugar de mantener un proceso de proxy en espacio de usuario escuchando en el socket (como ocurría antiguamente en Docker), Netavark gestiona la redirección de puertos directamente en el kernel mediante reglas DNAT de **nftables**. Puedes comprobar que el puerto está publicado inspeccionando el contenedor con `podman ps` y verificando la respuesta HTTP en loopback con `curl -I http://127.0.0.1:8080/`.

### Paso G: Verificación y Conexión desde el Cliente

Para verificar el servicio desde tu estación de trabajo (asumiendo que utilizaste el dominio de laboratorio `secretos.linenes.tld`):

1. **Configura la resolución local en tu estación de trabajo (Fedora Linux):**
   Añade la IP pública de tu servidor al archivo `/etc/hosts`:

   ```bash
   echo "<IP_DEL_SERVIDOR> secretos.linenes.tld" | sudo tee -a /etc/hosts
   ```

1. **Comprobación rápida con curl:**

   ```bash
   curl -kI https://secretos.linenes.tld/
   ```

   El parámetro `-k` le indica a `curl` que confíe temporalmente en el certificado auto-firmado emitido por la CA interna de Caddy. Recibirás una respuesta HTTP `200 OK`.

1. **Acceso desde el navegador:**
   Abre tu navegador e ingresa a `https://secretos.linenes.tld`.
   *(Si el navegador muestra una advertencia de seguridad debido a la CA local auto-firmada, acéptala para continuar al panel).*

1. **Crear tu cuenta administrativa:**
   * Haz clic en **Crear cuenta** (*Create Account*).
   * Ingresa tu correo electrónico, un nombre y una contraseña maestra segura.
   * Inicia sesión en el baúl web de contraseñas.
   * ¡Tu gestor de contraseñas privado y cifrado de punto a punto está completamente operativo!

---

## 3. Automatización Declarativa con OpenTofu (Infraestructura como Código)

Ahora que comprendes con precisión matemática qué hace cada archivo, servicio y política de SELinux, automatizaremos todo el proceso utilizando **OpenTofu** y la API de **Cherry Servers**.

### Clonar el Repositorio y Explorar Manifiestos

Cámbiate a la rama del Cómo y navega a la carpeta de OpenTofu:

```bash
cd ~/Projects/cherry-servers
git checkout 02-caddy-podman
cd 02-caddy-podman/tofu
```

Nuestra estructura de archivos sigue un diseño plano y transparente:

* `provider.tf`: Define los requerimientos del proveedor `cherryservers/cherryservers` (`~> 1.5.3`).
* `variables.tf`: Declara las variables del despliegue, incluyendo `server_name` (`0.caddy.linenes.tld`) y `vault_domain` (`secretos.linenes.tld`).
* `main.tf`: Configura la clave SSH, aprovisiona la instancia Cloud VPS e inyecta dinámicamente el script [`scripts/bootstrap.bash`](file:///home/renich/Projects/cherry-servers/02-caddy-podman/scripts/bootstrap.bash) evaluando si el dominio requiere certificados locales (`tls internal`) o certificados públicos ACME.
* `outputs.tf`: Muestra la IP pública, la URL del baúl, la línea para `/etc/hosts` y el comando SSH.
* `terraform.tfvars.example`: Plantilla de variables para tus credenciales.

### El Script de Arranque Declarativo (`scripts/bootstrap.bash`)

El script de arranque automatiza idénticamente los pasos manuales que realizamos:

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
...
# 1. Habilitar repositorios EPEL 10 y COPR oficial de Caddy
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable || true
dnf -y copr enable @caddy/caddy

# 2. Instalar Caddy y Podman
dnf -y install caddy podman firewalld curl jq

# 3. Directorio FHS 3.0
mkdir -p /srv/vaultwarden/data
chmod 750 /srv/vaultwarden /srv/vaultwarden/data

# 4. Declarar Podman Quadlet
cat << 'EOF' > /etc/containers/systemd/vaultwarden.container
...
EOF

# 5. Iniciar Vaultwarden
systemctl daemon-reload
systemctl enable --now vaultwarden.service

# 6. Configurar Caddyfile
...

# 7. SELinux Enforcing
setsebool -P httpd_can_network_connect 1

# 8. Firewall
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
systemctl enable --now caddy.service
```

### Configurar Variables Locales y Desplegar (`tofu apply`)

Copia la plantilla de variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tu token y clave SSH:

```hcl
cherry_auth_token = "TU_API_TOKEN_AQUI"
project_id        = 123456
ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... tu_correo@ejemplo.com"
server_name       = "0.caddy.linenes.tld"
vault_domain      = "secretos.linenes.tld"
server_plan       = "Cloud VPS 1"
server_image      = "centos_stream_10_64bit"
spot_instance     = false
```

Inicializa y despliega la infraestructura:

```bash
tofu init
tofu plan
tofu apply
```

Confirma escribiendo `yes`. En aproximadamente 2 minutos, la instancia estará lista y OpenTofu reportará los datos de conexión:

```text
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

hosts_entry = "84.32.109.60 secretos.linenes.tld"
server_ip = "84.32.109.60"
ssh_command = "ssh root@84.32.109.60"
vault_domain = "secretos.linenes.tld"
vaultwarden_url = "https://secretos.linenes.tld"
```

Copia la salida `hosts_entry` a tu archivo local `/etc/hosts` y navega a la URL indicada para disfrutar de tu servidor completamente aprovisionado.

---

## 4. Destrucción del Servidor y Control de Costos

Una vez concluida tu práctica o si deseas apagar el laboratorio para evitar consumos residuales:

Desde la carpeta `02-caddy-podman/tofu`:

```bash
tofu destroy
```

Confirma escribiendo `yes`. OpenTofu eliminará la instancia en Cherry Servers y desregistrará la clave SSH:

```text
Destroy complete! Resources: 2 destroyed.
```

Recuerda remover la entrada temporal agregada en `/etc/hosts` en tu máquina de escritorio. El costo total de haber ejecutado este laboratorio completo ronda entre **~$0.02 y $0.03 USD**.

---

## 5. Retos de Aprendizaje y Práctica

Para consolidar tu dominio sobre proxies inversos, contenedores y SELinux, te invito a resolver estos 3 desafíos prácticos:

1. **Reto 1: Deshabilitar registros públicos y habilitar token de administración**
   * Una vez creada tu cuenta de usuario principal, un gestor de contraseñas en internet no debe permitir que cualquier desconocido cree cuentas nuevas.
   * Modifica el archivo Quadlet de Vaultwarden (`/etc/containers/systemd/vaultwarden.container`) para establecer `SIGNUPS_ALLOWED=false` y configurar una variable `ADMIN_TOKEN` con una cadena criptográfica generada mediante `openssl rand -base64 32`.
   * Recarga Systemd (`systemctl daemon-reload` y reinicia el servicio). Comprueba que el formulario de registro web rechace nuevos usuarios, pero que puedas acceder a la consola administrativa en `https://secretos.linenes.tld/admin`.

1. **Reto 2: Respaldo en caliente de SQLite mediante Systemd Timers**
   * Vaultwarden utiliza SQLite por defecto en `/srv/vaultwarden/data/db.sqlite3`. Copiar un archivo SQLite en caliente con `cp` puede corromper la base de datos si ocurre durante una transacción.
   * Diseña una unidad de servicio `vaultwarden-backup.service` y un temporizador `vaultwarden-backup.timer` en `/etc/systemd/system/` que invoque periódicamente el comando seguro de respaldo en línea:
     `sqlite3 /srv/vaultwarden/data/db.sqlite3 ".backup '/srv/vaultwarden/backups/db-$(date +%F).sqlite3'"`
   * Asegúrate de crear el directorio de destino bajo FHS 3.0 con los permisos adecuados y programa el temporizador para ejecutarse todas las noches.

1. **Reto 3: Migrar Caddy a un contenedor Podman con red compartida interna**
   * En este Cómo instalamos Caddy como RPM nativo y Vaultwarden en Podman. Modifica la arquitectura para ejecutar **ambos servicios dentro de Podman** declarados como dos Quadlets (`caddy.container` y `vaultwarden.container`).
   * Crea un archivo de red interna declarativa de Quadlet (`vaultwarden.network`) de modo que Caddy y Vaultwarden se comuniquen a través del resolver DNS interno de Podman por el nombre del contenedor (ej. `reverse_proxy vaultwarden:80`) sin publicar puertos en `127.0.0.1`.
   * Analiza cómo cambian los requerimientos de puertos en el host y las directivas de SELinux.

---

### Dudas y Preguntas

¿Tienes preguntas sobre Podman Quadlets, configuración de Caddy o políticas de SELinux? Abre un Issue en el repositorio de GitLab o súmate a las conversaciones de la comunidad. ¡Nos vemos en el **Cómo 03: Reconstrucción y Automatización con Ansible**!
