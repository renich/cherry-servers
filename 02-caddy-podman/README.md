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

Para garantizar una experiencia de aprendizaje idéntica a producción, utilizaremos dominios públicos basados en **`sslip.io`**. Esto permite que Caddy obtenga **certificados SSL/TLS auténticos y válidos emitidos por Let's Encrypt de forma automática**, sin necesidad de comprar un dominio, sin modificar archivos `/etc/hosts` y **sin aceptar excepciones o advertencias de seguridad en tu navegador**.

Fieles a nuestra filosofía **«Manual Primero, Automatización Después»**, primero realizaremos todo el despliegue a mano en la terminal mediante SSH, entendiendo cada directiva, contexto de SELinux y regla de firewall. Posteriormente, empaquetaremos la solución completa en un despliegue declarativo e instantáneo con **OpenTofu**.

---

## 1. Prerrequisitos del Laboratorio

1. Un servidor con **CentOS Stream 10** en la nube (o máquina virtual local con IP pública) con acceso SSH como `root` mediante clave pública Ed25519 (`~/.ssh/id_ed25519.pub`). Si aún no tienes un par de llaves:

   ```bash
   ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"
   ```

1. Clientes y herramientas en tu estación de trabajo (**Fedora Linux**):

   * Navegador web moderno (Firefox, Chromium) o la extensión oficial de Bitwarden.
   * Utilidades de red y OpenTofu instaladas:

   ```bash
   sudo dnf -y install curl jq opentofu
   ```

1. **Resolución de Nombres Pública y Automática (`sslip.io`):**
   `sslip.io` es un servicio de DNS público sin estado (*stateless wildcard DNS*) incluido en la *Public Suffix List* (PSL) oficial. Mapea cualquier dirección IP directamente a un nombre de dominio (por ejemplo, `84.32.149.15.sslip.io` resuelve globalmente a `84.32.149.15`). Esto permite que Let's Encrypt valide desafíos ACME y emita certificados oficiales con candado verde para cualquier servidor en la nube sin costo ni configuración previa. Si dispones de un dominio propio (ej. `secretos.tudominio.com`), podrás usarlo indistintamente.

---

## 2. Construcción y Configuración Manual vía SSH (El Núcleo del Aprendizaje)

Conéctate por SSH a tu servidor:

```bash
ssh root@<IP_DEL_SERVIDOR>
```

### Paso A: Arquitectura de la Solución (Caddy RPM, Podman Quadlets y FQDN)

Nuestra arquitectura divide responsabilidades de forma limpia y robusta:

1. **Caddy en el Host (RPM):** Se ejecuta directamente en el sistema operativo base. Tiene acceso directo a los puertos privilegiados `80/tcp` y `443/tcp`, resuelve el desafío ACME HTTP-01 con Let's Encrypt y reenvía el tráfico internamente.
1. **Vaultwarden en Podman Quadlet:** En lugar de depender de un demonio monolítico en segundo plano (como Docker), Podman Quadlet traduce archivos de definición declarativos (`.container`) en unidades nativas de **Systemd**. El contenedor se inicia, monitorea y reinicia como cualquier otro servicio del sistema operativo, registrando su salida directamente en `journald`.
1. **Aislamiento en Loopback:** El contenedor de Vaultwarden expone su puerto interno únicamente en la interfaz de bucle invertido (`127.0.0.1:8080`). Nunca se expone a interfaces públicas (`0.0.0.0`), garantizando que nadie pueda evadir el proxy de Caddy.
1. **Seguridad con SELinux:** Operamos con SELinux en modo **Enforcing**. Habilitamos el booleano `httpd_can_network_connect` para permitir que Caddy se comunique con el backend local, y etiquetamos los volúmenes del contenedor con `:Z` para que los procesos confinados persistan datos en `/srv/vaultwarden/data` bajo categorías MCS privadas.

### Paso B: Habilitar Repositorios e Instalar Paquetes RPM

Habilita **EPEL 10**, **CRB** y el repositorio oficial de Caddy en COPR (`@caddy/caddy`):

```bash
# 1. Habilitar EPEL 10 y herramientas auxiliares
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable

# 2. Habilitar el repositorio oficial de Caddy
dnf -y copr enable @caddy/caddy

# 3. Instalar Caddy, Podman, utilerías de actualización y herramientas de diagnóstico
dnf -y install caddy podman firewalld curl jq certbot dnf-automatic
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
* `AutoUpdate=registry`: Indica a Podman que este contenedor debe ser actualizado automáticamente cuando exista una nueva imagen en el registro.

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

Puedes comprobar que el puerto responde internamente en loopback:

```bash
curl -I http://127.0.0.1:8080/
```

Recibirás un encabezado HTTP `200 OK` generado por el servidor Rust de Vaultwarden.

### Paso E: Configuración del Proxy Inverso en Caddy (`/etc/caddy/Caddyfile`)

Determinamos la IP pública del servidor y construimos el nombre de dominio público con `sslip.io`:

```bash
# Obtener la IP pública del servidor
SERVER_IP=$(curl -s4 https://icanhazip.com || ip -4 addr show scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
VAULT_DOMAIN="${SERVER_IP}.sslip.io"

echo "Configurando Caddy para el dominio público: ${VAULT_DOMAIN}"

# Crear directorio de registros
mkdir -p /var/log/caddy

cat << EOF > /etc/caddy/Caddyfile
{
    admin off
}

${VAULT_DOMAIN} {
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

Al utilizar `${SERVER_IP}.sslip.io`, Caddy contactará a **Let's Encrypt** automáticamente al arrancar. Let's Encrypt validará que el dominio resuelve a tu IP pública y expedirá un certificado TLS de confianza pública de inmediato.

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
* Asigna categorías MCS (*Multi-Category Security*) aleatorias y exclusivas (por ejemplo, `s0:c662,c731`) que aíslan los archivos de esta instancia frente a cualquier otro contenedor en el sistema.

Verifiquemos el contexto resultante en el sistema de archivos:

```bash
ls -Zd /srv/vaultwarden/data
```

Verás una salida con el tipo correcto `container_file_t`:

```text
system_u:object_r:container_file_t:s0:c662,c731 /srv/vaultwarden/data
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

Comprueba que Caddy esté escuchando en los puertos privilegiados:

```bash
ss -tlpn | grep -E ':(80|443)'
```

> **¿Por qué el puerto 8080 no aparece en `ss -tlpn`?**
>
> En versiones modernas de Podman sobre CentOS Stream y Fedora, la pila de red predeterminada es **Netavark**. En lugar de mantener un proceso de proxy en espacio de usuario escuchando en el socket (como ocurría antiguamente en Docker), Netavark gestiona la redirección de puertos directamente en el kernel mediante reglas DNAT de **nftables**. Puedes comprobar que el puerto está publicado inspeccionando el contenedor con `podman ps` y verificando la respuesta HTTP en loopback con `curl -I http://127.0.0.1:8080/`.

### Paso G: Verificación y Conexión desde el Cliente

Para verificar el servicio desde tu estación de trabajo (asumiendo que tu servidor tiene la IP `84.32.149.15`):

1. **Comprobación directa con curl (Validación estricta de TLS):**

   ```bash
   curl -I https://<IP_DEL_SERVIDOR>.sslip.io/
   ```

   Observa que la petición se realiza **sin banderas `-k` ni `--insecure`**. Recibirás una respuesta HTTP `200 OK` con cabeceras `server: Rocket` y `via: 1.1 Caddy` firmada por Let's Encrypt.

1. **Acceso desde el navegador:**
   Abre tu navegador e ingresa a `https://<IP_DEL_SERVIDOR>.sslip.io`.
   Observarás el **candado verde de conexión segura** activo de forma inmediata, sin advertencias de certificado ni excepciones.

1. **Crear tu cuenta administrativa:**
   * Haz clic en **Crear cuenta** (*Create Account*).
   * Ingresa tu correo electrónico, un nombre y una contraseña maestra segura.
   * Inicia sesión en el baúl web de contraseñas.
   * ¡Tu gestor de contraseñas privado y cifrado de punto a punto está completamente operativo!

---

## 3. Mantenimiento Continuo: Actualizaciones del Sistema y del Contenedor

Un servidor en producción requiere mecanismos confiables para aplicar parches de seguridad de forma predecible y automática.

### A. Actualizaciones del Sistema Operativo con `dnf-automatic`

Para mantener CentOS Stream 10 protegido contra vulnerabilidades del kernel y paquetes base sin intervención manual:

1. Configura `dnf-automatic` para aplicar actualizaciones de forma desatendida:

   ```bash
   sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
   ```

1. Habilita el temporizador de Systemd:

   ```bash
   systemctl enable --now dnf-automatic.timer
   ```

Systemd ejecutará la verificación e instalación diaria de paquetes RPM, asegurando que parches de seguridad críticos se instalen puntualmente.

### B. Actualizaciones Automáticas del Contenedor con Podman Quadlet

Gracias a la directiva `AutoUpdate=registry` configurada en el archivo Quadlet (`vaultwarden.container`), Podman cuenta con un mecanismo nativo de actualización continua integrado con Systemd:

1. **Habilitar el temporizador de actualización de Podman:**

   ```bash
   systemctl enable --now podman-auto-update.timer
   ```

   Este temporizador de Systemd se ejecuta diariamente. Inspecciona los contenedores en ejecución, consulta el registro upstream (`docker.io`) y, si detecta un nuevo digest de la imagen, descarga la capa actualizada y reinicia el servicio `vaultwarden.service` automáticamente. Si el contenedor falla tras la actualización, Podman realiza un rollback automático a la versión anterior.

1. **Ejecutar una actualización manual bajo demanda:**
   Puedes disparar la comprobación y actualización en cualquier momento ejecutando:

   ```bash
   podman auto-update
   ```

1. **Limpieza higiénica de imágenes antiguas:**
   Tras sucesivas actualizaciones, elimina imágenes intermedias huérfanas con:

   ```bash
   podman image prune -f
   ```

---

## 4. Automatización Declarativa con OpenTofu (Infraestructura como Código)

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
* `variables.tf`: Declara las variables del despliegue, con `vault_domain = "auto"` para auto-generar `<IP>.sslip.io` con Let's Encrypt.
* `main.tf`: Configura la clave SSH, aprovisiona la instancia Cloud VPS e inyecta dinámicamente el script [`scripts/bootstrap.bash`](file:///home/renich/Projects/cherry-servers/02-caddy-podman/scripts/bootstrap.bash).
* `outputs.tf`: Muestra la IP pública, la URL con HTTPS de Let's Encrypt y el comando SSH.
* `terraform.tfvars.example`: Plantilla de variables para tus credenciales.

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
vault_domain      = "auto"
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

Confirma escribiendo `yes`. En aproximadamente 2 minutos, la instancia estará lista y OpenTofu reportará los datos de conexión con tu URL pública lista:

```text
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

server_ip = "84.32.149.15"
ssh_command = "ssh root@84.32.149.15"
vault_domain = "84.32.149.15.sslip.io"
vaultwarden_url = "https://84.32.149.15.sslip.io"
```

Haz clic en la URL `vaultwarden_url` en tu terminal y accederás directamente a tu baúl protegido con HTTPS oficial.

---

## 5. Destrucción del Servidor, Higiene Criptográfica y Control de Costos

Una vez concluida tu práctica o si deseas apagar el laboratorio para evitar consumos residuales, sigue estos pasos de buena higiene operativa.

### Higiene Criptográfica: Revocar el Certificado TLS ante Let's Encrypt

En infraestructuras en la nube efímeras, cuando destruyes una máquina virtual, su dirección IP pública vuelve al grupo común (*pool*) del proveedor y eventualmente será asignada a otro cliente. Por higiene criptográfica y responsabilidad de seguridad, es una buena práctica revocar el certificado emitido para esa dirección IP antes de descartar el servidor:

Conéctate por SSH a tu servidor y revoca el certificado utilizando `certbot` y las llaves almacenadas por Caddy:

```bash
SERVER_IP=$(curl -s4 https://icanhazip.com)
DOMAIN="${SERVER_IP}.sslip.io"

certbot revoke \
  --cert-path "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt" \
  --key-path "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.key" \
  --reason cessationOfOperation \
  --no-delete-after-revoke \
  --non-interactive
```

Elimina las copias locales de llaves y certificados en Caddy:

```bash
rm -rf /var/lib/caddy/.local/share/caddy/certificates/
```

### Liberación del Dominio Temporal (`sslip.io`)

A diferencia de los dominios DNS tradicionales que requieren cancelar suscripciones o borrar registros en un panel de control, `sslip.io` es un servicio de DNS algorítmico **sin estado** (*stateless*). No almacena bases de datos con tu nombre.

En el instante en que destruyes la máquina virtual en Cherry Servers, la dirección IP se desasocia de tu cuenta. Ninguna petición posterior llegará a tus datos ni a tu servicio.

### Destrucción de la Infraestructura con OpenTofu

Desde la carpeta `02-caddy-podman/tofu` en tu estación de trabajo:

```bash
tofu destroy
```

Confirma escribiendo `yes`. OpenTofu eliminará la instancia en Cherry Servers y desregistrará la clave SSH:

```text
Destroy complete! Resources: 2 destroyed.
```

El costo total de haber ejecutado este laboratorio completo ronda entre **~$0.02 y $0.03 USD**.

---

## 6. Retos de Aprendizaje y Práctica

Para consolidar tu dominio sobre proxies inversos, contenedores y SELinux, te invito a resolver estos 3 desafíos prácticos:

1. **Reto 1: Deshabilitar registros públicos y habilitar token de administración**
   * Una vez creada tu cuenta de usuario principal, un gestor de contraseñas en internet no debe permitir que cualquier desconocido cree cuentas nuevas.
   * Modifica el archivo Quadlet de Vaultwarden (`/etc/containers/systemd/vaultwarden.container`) para establecer `SIGNUPS_ALLOWED=false` y configurar una variable `ADMIN_TOKEN` con una cadena criptográfica generada mediante `openssl rand -base64 32`.
   * Recarga Systemd (`systemctl daemon-reload` y reinicia el servicio). Comprueba que el formulario de registro web rechace nuevos usuarios, pero que puedas acceder a la consola administrativa en `https://<TU_DOMINIO>/admin`.

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
