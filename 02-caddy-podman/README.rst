=====================================================================================
Cómo desplegar Vaultwarden en Podman Quadlets con Caddy y SELinux en CentOS Stream 10
=====================================================================================

:Módulo: Cómo 02: Proxy Inverso con Caddy y Vaultwarden en Podman con SELinux
:Versión: ``v1.0.0``
:Fecha: ``2026-08-19``
:Directorio: `02-caddy-podman <https://gitlab.com/renich/cherry-servers/-/tree/master/02-caddy-podman>`__
:Licencia: `GFDL-1.3-or-later <../LICENSE>`__
:Tipo de instancia: Cloud VPS 1, ``B1-1-1gb-20s-shared``, Gen 2 con 1 vCPU, 1 GB RAM y 20 GB SSD, o Cloud VPS 2
:Costo por hora: ~$0.015 EUR/hora, ~$0.016 USD/hora
:Tiempo promedio: 1 a 2 horas
:Gasto estimado total: ~$0.03 USD

¡Hola! 👋

Te doy la bienvenida al **segundo Cómo** de esta serie práctica de infraestructura y administración de sistemas en Linux para la comunidad de software libre.

En entornos reales de producción y laboratorios domésticos o *homelabs*, exponer contenedores abriendo puertos arbitrarios directamente a internet, como ``:8080``, ``:3000`` o ``:9000``, es una mala práctica de seguridad y arquitectura. El patrón estándar coloca al frente un **Proxy Inverso** seguro que escucha en los puertos estándar HTTP/HTTPS, ``80`` y ``443``, gestiona la terminación TLS y enruta el tráfico mediante *Virtual Hosting* con SNI/FQDN hacia servicios internos aislados en loopback.

Todo el laboratorio corre sobre **CentOS Stream 10**. A diferencia de los antiguos clones cerrados posteriores al lanzamiento de RHEL, y frente al mito frecuente de que «CentOS murió», CentOS Stream es la rama abierta de entrega continua aguas arriba de RHEL 10: ofrece estabilidad de ABI/API durante todo el ciclo mayor, contribución pública transparente, **SELinux en modo Enforcing**, **Caddy** nativo en **EPEL 10** y soporte de primera clase para **Podman Quadlets**.

En esta práctica desplegarás **Vaultwarden**, la implementación ligera y libre en Rust del backend de Bitwarden, gestionada por **Podman Quadlets** en **Systemd**, confinada bajo **SELinux en modo Enforcing** y publicada mediante **Caddy** instalado como paquete RPM oficial. Con ``sslip.io``, Caddy obtendrá certificados TLS reales emitidos por **Let's Encrypt** de forma automática, sin comprar dominio, sin editar ``/etc/hosts`` y con una **conexión HTTPS verificada sin advertencias** en tu navegador.

Siguiendo la regla pedagógica **«Manual Primero, Automatización Después»**, primero construirás cada capa a mano vía SSH entendiendo sus permisos, contextos SELinux y reglas de cortafuegos; después automatizarás el entorno completo de forma declarativa con **OpenTofu**.

1. Prerrequisitos del Laboratorio
=================================

#. Un servidor con **CentOS Stream 10** y dirección IP pública accesible, o una máquina virtual local, con acceso SSH como ``root`` exclusivamente mediante clave pública Ed25519 en ``~/.ssh/id_ed25519.pub``.

   * **Saldo promocional de $20 USD:** Puedes realizar esta práctica en la nube sin costo inicial gracias al patrocinio de **Cherry Servers**. Regístrate en `este enlace de bienvenida <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__ con el código ``LinuxEnEspanol`` para recibir **$20 USD de crédito**.
   * **Cómo crear tu servidor manual:** En el portal de Cherry Servers crea una instancia con imagen **CentOS Stream 10**, plan **Cloud VPS 1** ``B1-1-1gb-20s-shared``, asociando tu clave pública Ed25519. Si prefieres crear la máquina vacía desde la terminal sin configurar el servicio todavía, puedes usar los manifiestos de OpenTofu de la Sección 3 estableciendo ``enable_bootstrap = false``.
   * Si aún no tienes un par de llaves Ed25519 en tu estación de trabajo, genéralo y cárgalo en ``ssh-agent``:

   .. code-block:: bash

      ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"
      eval "$(ssh-agent -s)"
      ssh-add ~/.ssh/id_ed25519

   .. note::
      **Máquinas virtuales locales bajo NAT:** Los desafíos ACME HTTP-01 de Let's Encrypt requieren una dirección IP pública enrutable desde internet. Si practicas en una VM local bajo NAT o en un rango privado RFC 1918 como ``192.168.x.x``, Let's Encrypt no podrá validar el dominio; en el Paso E verás cómo usar ``DOMINIO_VAULT="vault.lan"`` con ``tls internal`` para que Caddy emita un certificado local autofirmado.

#. Herramientas y clientes en tu estación de trabajo con **Fedora Linux**:

   * Navegador web moderno como Firefox o Chromium, o la extensión oficial de Bitwarden.
   * Clientes SSH, Git, utilidades de red y OpenTofu instalados con DNF:

   .. code-block:: bash

      sudo dnf -y install openssh-clients git-core curl jq opentofu

#. **Resolución DNS automática con** ``sslip.io`` **:** ``sslip.io`` es un servicio DNS público sin estado, *stateless wildcard DNS*, incluido en la *Public Suffix List*. Traduce cualquier dirección IPv4 a un nombre de dominio; por ejemplo, ``203.0.113.15.sslip.io`` resuelve a ``203.0.113.15``. Así Let's Encrypt valida el desafío ACME y emite un certificado oficial para tu servidor sin costo ni configuración DNS previa. Si cuentas con un dominio propio, como ``secretos.tudominio.com``, puedes usarlo en su lugar.

2. Construcción y Configuración Manual vía SSH, El Núcleo del Aprendizaje
=========================================================================

**En tu estación de trabajo con Fedora Linux**, identifica la dirección IPv4 de tu servidor:

* En **Cherry Servers**, abre el panel de tu instancia y copia el valor del campo **Primary IP**.
* En una **VM local**, consúltala desde su consola con ``ip -4 -o addr show scope global``.

Exporta esa dirección en la variable ``IP_DEL_SERVIDOR``, sustituyendo ``203.0.113.15`` por la IP real de tu servidor, y abre la sesión SSH directa como ``root``:

.. code-block:: bash

   export IP_DEL_SERVIDOR="203.0.113.15"
   ssh "root@${IP_DEL_SERVIDOR}"

A partir de este punto, ejecuta los **Pasos A a F dentro de la terminal remota del servidor** como ``root``.

Paso A: Arquitectura de la Solución con Caddy RPM, Podman Quadlets y FQDN
-------------------------------------------------------------------------

La arquitectura separa cada responsabilidad de manera limpia:

#. **Caddy como paquete RPM nativo:** Se ejecuta en el sistema operativo anfitrión, escucha en los puertos privilegiados ``80/tcp`` y ``443/tcp``, completa los desafíos ACME HTTP-01 con Let's Encrypt y reenvía el tráfico hacia el backend local.
#. **Vaultwarden en Podman Quadlet:** En lugar de depender de un demonio monolítico como Docker, Podman Quadlet convierte un archivo declarativo ``.container`` en una unidad nativa de **Systemd**. Systemd arranca, supervisa y reinicia el contenedor automáticamente ante fallos y centraliza sus registros en ``journald``.
#. **Aislamiento en loopback:** Vaultwarden publica su puerto interno únicamente en ``127.0.0.1:8080``, nunca en ``0.0.0.0``. Nadie desde internet puede saltarse el proxy inverso ni el cifrado TLS de Caddy.
#. **Confinamiento con SELinux:** Operas con SELinux en modo **Enforcing**. Habilitas el booleano ``httpd_can_network_connect`` para que Caddy conecte al backend local, asignas el tipo ``httpd_log_t`` en ``/var/log/caddy`` para sus registros JSON y etiquetas el volumen del contenedor con ``:Z`` para aislar los datos en ``/srv/vaultwarden/data`` mediante categorías MCS privadas.

Paso B: Nombre de Host, Repositorios, Paquetes RPM y Firewalld
--------------------------------------------------------------

Primero define el nombre de host estructurado del servidor, habilita **EPEL 10** junto con **CRB** e instala los paquetes necesarios:

.. code-block:: bash

   # 1. Definir el nombre de host del nodo
   hostnamectl set-hostname 0.caddy.linenes.tld

   # 2. Habilitar repositorio EPEL 10 y CRB
   dnf -y install epel-release
   /usr/bin/crb enable

   # 3. Instalar Caddy, Podman, Firewalld, utilerías SELinux y herramientas base
   dnf -y install caddy podman firewalld curl jq dnf-automatic policycoreutils-python-utils

**Qué hace cada pieza nueva:**

* ``/usr/bin/crb enable``: Activa el repositorio *CodeReady Linux Builder*, indispensable porque múltiples paquetes de EPEL 10 dependen de bibliotecas y herramientas alojadas en CRB.
* ``policycoreutils-python-utils``: Instala ``semanage``, necesario para registrar contextos persistentes de SELinux como ``httpd_log_t`` sobre ``/var/log/caddy``.

Habilita y configura ``firewalld`` **antes** de iniciar el contenedor o Caddy, permitiendo únicamente tráfico web estándar además de SSH:

.. code-block:: bash

   systemctl --now enable firewalld
   firewall-cmd --permanent --add-service=http
   firewall-cmd --permanent --add-service=https
   firewall-cmd --reload
   firewall-cmd --list-all

* ``--permanent`` guarda las reglas en disco para que sobrevivan a reinicios sin alterar todavía la tabla activa; ``--reload`` aplica esa configuración persistente en caliente sin cortar tu sesión SSH. Configurar ``firewalld`` antes de los contenedores garantiza que el filtrado del host y las reglas de Netavark arranquen en orden limpio.

.. note::
   **¿Por qué priorizar EPEL sobre COPR?**

   En sistemas Enterprise Linux de producción, la prioridad pertenece siempre a los repositorios oficiales de la distribución, CentOS Stream BaseOS/AppStream, y a los paquetes firmados y mantenidos por la comunidad Fedora en **EPEL 10**, donde Caddy v2 ya viene empaquetado de forma nativa. Los repositorios comunitarios COPR se reservan para software ausente en EPEL.

Paso C: Estructura de Datos y Permisos bajo FHS 3.0
---------------------------------------------------

Bajo el estándar **FHS 3.0**, *Filesystem Hierarchy Standard*, los datos persistentes de servicios del sitio residen en ``/srv/<servicio>``. Crea el directorio donde Vaultwarden almacenará su base de datos SQLite y adjuntos:

.. code-block:: bash

   mkdir -p /srv/vaultwarden/data
   chmod 750 /srv/vaultwarden /srv/vaultwarden/data

Paso D: Declarar y Arrancar el Contenedor con Podman Quadlet
------------------------------------------------------------

**Quadlet** traduce archivos ``.container`` con sintaxis estándar de Systemd en unidades generadas dinámicamente. Crea ``/etc/containers/systemd/vaultwarden.container``:

.. code-block:: bash

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
   AutoUpdate=registry

   [Service]
   Restart=on-failure
   TimeoutStartSec=180

   [Install]
   WantedBy=multi-user.target default.target
   EOF

   chmod 644 /etc/containers/systemd/vaultwarden.container

**Directivas clave del Quadlet:**

* ``cat << 'EOF' >``: Las comillas simples en ``'EOF'`` indican a Bash que copie el contenido de forma literal, sin expandir variables dentro del bloque.
* ``PublishPort=127.0.0.1:8080:80``: Expone el puerto ``80`` interno del contenedor exclusivamente en ``127.0.0.1:8080`` del anfitrión.
* ``Volume=/srv/vaultwarden/data:/data:Z``: Monta el almacenamiento persistente aplicando la etiqueta privada ``container_file_t`` con una categoría MCS exclusiva para este contenedor.
* ``Environment=SIGNUPS_ALLOWED=true``: Permite crear tu primera cuenta durante la práctica. **Riesgo de seguridad:** dejar el registro público abierto en internet permite que cualquier desconocido cree cuentas en tu instancia; desactívalo en cuanto crees tu usuario principal, como practicarás en el Reto 1.
* ``Restart=on-failure`` y ``TimeoutStartSec=180``: Instruyen a Systemd a reiniciar Vaultwarden automáticamente ante cualquier fallo inesperado y conceden hasta 180 segundos para descargar la imagen en el primer arranque.
* ``AutoUpdate=registry``: Habilita la actualización automática de la imagen mediante ``podman-auto-update``.

Recarga Systemd para generar la unidad e inicia el servicio:

.. code-block:: bash

   systemctl daemon-reload
   systemctl start vaultwarden.service
   systemctl --no-pager status vaultwarden.service

.. note::
   **Sobre unidades generadas por Quadlet:** Los archivos ``.container`` con sección ``[Install]`` quedan habilitados automáticamente en ``/run/systemd/generator/`` tras ``systemctl daemon-reload`` y en cada reinicio. Por eso no debes ejecutar ``systemctl enable vaultwarden.service``; basta con ``systemctl start vaultwarden.service``.

.. tip::
   Ejecuta ``systemctl cat vaultwarden.service`` para inspeccionar la unidad Systemd completa generada a partir de tu archivo ``.container``.

Comprueba que Vaultwarden responde localmente en loopback:

.. code-block:: bash

   curl -I http://127.0.0.1:8080/

Debes recibir un encabezado ``HTTP/1.1 200 OK`` servido por Vaultwarden.

Paso E: Configuración del Proxy Inverso en Caddy
------------------------------------------------

Detecta la dirección IPv4 pública del servidor filtrando interfaces virtuales de contenedores y rangos privados RFC 1918, y construye el nombre de dominio público con ``sslip.io``:

.. code-block:: bash

   IP_PUBLICA=$(curl -fs4 --connect-timeout 5 --max-time 10 https://icanhazip.com || ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 !~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
   if [[ -z "${IP_PUBLICA}" ]]; then
     printf '%s\n' "Error: no se detectó una IPv4 pública; asigna DOMINIO_VAULT manualmente." >&2
   else
     DOMINIO_VAULT="${IP_PUBLICA}.sslip.io"
     printf 'Configurando Caddy para el dominio público: %s\n' "${DOMINIO_VAULT}"
   fi

.. note::
   **Si practicas en una VM local bajo NAT:** Omite la consulta a ``icanhazip.com`` y define directamente ``DOMINIO_VAULT="vault.lan"``. Luego agrega ``tls internal`` dentro del bloque de sitio en ``/etc/caddy/Caddyfile`` y añade la línea correspondiente a ``vault.lan`` en el archivo ``/etc/hosts`` de tu estación de trabajo apuntando a ``${IP_DEL_SERVIDOR}``.

Crea los directorios, genera ``/etc/caddy/Caddyfile``, formatéalo y aplica permisos estrictos de mínimo privilegio. Observa que aquí se usa ``cat << EOF >`` sin comillas alrededor de ``EOF`` para que Bash expanda ``${DOMINIO_VAULT}`` dentro del archivo, a diferencia del ``cat << 'EOF' >`` literal del Paso D:

.. code-block:: bash

   mkdir -p /etc/caddy /var/log/caddy

   cat << EOF > /etc/caddy/Caddyfile
   ${DOMINIO_VAULT} {
       # Proxy inverso al contenedor local en loopback; Caddy gestiona X-Forwarded-* automáticamente
       reverse_proxy 127.0.0.1:8080

       log {
           output file /var/log/caddy/vaultwarden.access.log
           format json
       }
   }
   EOF

   caddy fmt --overwrite /etc/caddy/Caddyfile
   chown root:caddy /etc/caddy /etc/caddy/Caddyfile
   chmod 750 /etc/caddy
   chmod 640 /etc/caddy/Caddyfile
   chown caddy:caddy /var/log/caddy
   chmod 750 /var/log/caddy

Con ``root:caddy`` y permisos ``750``/``640``, el demonio ``caddy`` puede leer su configuración sin tener permiso de escritura sobre ella, mientras que ``caddy:caddy`` ``750`` sobre ``/var/log/caddy`` le permite escribir únicamente en su directorio de registros. Todavía no arranques ``caddy.service``: primero configura SELinux y valida la configuración en el Paso F.

Paso F: SELinux a Fondo en Modo Enforcing, Validación y Arranque de Caddy
-------------------------------------------------------------------------

Continúa **en el servidor remoto vía SSH**. CentOS Stream 10 opera con **SELinux en modo Enforcing**, lo que exige configurar correctamente tanto la conexión de red saliente de Caddy como el etiquetado de su directorio de registros.

1. Diagnóstico del bloqueo de SELinux y el porqué
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

El binario de Caddy se ejecuta confinado bajo el dominio ``httpd_t``. Por diseño, la política predeterminada de SELinux prohíbe que un servidor web inicie conexiones TCP salientes hacia otros puertos locales mediante el permiso ``name_connect``. Sin autorización, cualquier petición al proxy terminaría en **502 Bad Gateway** con una denegación AVC similar a esta:

.. code-block:: text

   type=AVC msg=audit(1724021234.567:123): avc:  denied  { name_connect } for  pid=12345 comm="caddy" dest=8080 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:http_cache_port_t:s0 tclass=tcp_socket permissive=0

2. Solución canónica mediante booleanos de SELinux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En lugar de desactivar SELinux, habilita de forma persistente el booleano diseñado para proxies inversos y verifica el estado activo:

.. code-block:: bash

   setsebool -P httpd_can_network_connect 1
   getenforce
   getsebool httpd_can_network_connect

.. note::
   Aunque el paquete RPM de Caddy en EPEL 10 puede activar este booleano al instalarse, comprobarlo explícitamente con ``getenforce`` y ``getsebool`` es práctica esencial de SRE al depurar proxies como Caddy, Nginx o Apache.

3. Contexto persistente en ``/var/log/caddy`` y validación como usuario ``caddy``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En EPEL 10, crear ``/var/log/caddy`` a mano le hereda el contexto genérico ``var_log_t``. Bajo SELinux Enforcing, el dominio ``httpd_t`` solo puede escribir registros en rutas etiquetadas como ``httpd_log_t``; sin ese contexto, ``caddy.service`` falla al arrancar por denegación de escritura sobre ``vaultwarden.access.log``. Registrar la regla con ``semanage fcontext`` hace que el tipo ``httpd_log_t`` persista ante futuros reetiquetados del sistema.

Asimismo, validar la configuración con ``runuser -u caddy -- caddy validate`` en vez de ejecutarlo como ``root`` garantiza que el usuario sin privilegios ``caddy`` realmente pueda leer ``/etc/caddy/Caddyfile`` con los permisos ``640`` y evita crear archivos auxiliares con dueño ``root``. Reaplicar ``restorecon`` antes y después asegura contextos limpios antes de levantar el servicio:

.. code-block:: bash

   semanage fcontext -a -t httpd_log_t '/var/log/caddy(/.*)?'
   restorecon -Rv /etc/caddy /var/log/caddy
   runuser -u caddy -- caddy validate --config /etc/caddy/Caddyfile
   restorecon -Rv /etc/caddy /var/log/caddy

4. Etiquetado de volúmenes de contenedor con ``:Z``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Vaultwarden corre bajo el contexto ``container_t``. Gracias a ``Volume=/srv/vaultwarden/data:/data:Z`` en el Quadlet, Podman aplicó ``container_file_t`` con categorías MCS aleatorias y exclusivas que aíslan esta base de datos de cualquier otro contenedor.

.. warning::
   **¿Por qué no ejecutas** ``restorecon`` **en** ``/srv/vaultwarden`` **?**

   Ejecutar ``restorecon`` sobre ``/srv/`` restablecería el contexto de ``/srv/vaultwarden/data`` al tipo genérico ``var_t``, destruyendo el etiquetado MCS de ``:Z`` y bloqueando el acceso de Vaultwarden a su base de datos SQLite.

Verifica ambos contextos SELinux en un solo paso:

.. code-block:: bash

   ls -Zd /srv/vaultwarden/data /var/log/caddy

Debes ver ``container_file_t`` con categoría MCS en el volumen de Vaultwarden y ``httpd_log_t`` en los registros de Caddy:

.. code-block:: text

   system_u:object_r:container_file_t:s0:c662,c731 /srv/vaultwarden/data
   system_u:object_r:httpd_log_t:s0 /var/log/caddy

5. Arranque de Caddy y auditoría de red y SELinux
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Ahora habilita e inicia ``caddy.service``, comprueba los puertos de escucha, las reglas activas de Firewalld y confirma que no existan denegaciones AVC recientes:

.. code-block:: bash

   systemctl --now enable caddy.service
   systemctl --no-pager status caddy.service
   ss -tlpn | grep -E ':(80|443)'
   firewall-cmd --list-all
   ausearch -m AVC,USER_AVC -ts recent </dev/null || true

En ``ss -tlpn``, las banderas muestran sockets TCP, ``-t``, en estado de escucha, ``-l``, junto con el proceso propietario, ``-p``, y puertos numéricos sin resolución DNS, ``-n``.

.. note::
   **¿Por qué el puerto 8080 no aparece en** ``ss -tlpn`` **?**

   En CentOS Stream 10, la pila de red moderna de Podman es **Netavark**, que publica puertos mediante reglas DNAT en **nftables** directamente en el kernel en lugar de abrir un proceso proxy en espacio de usuario. Puedes confirmar el mapeo con ``podman ps`` y ``curl -I http://127.0.0.1:8080/``.

Paso G: Verificación y Conexión desde tu Estación de Trabajo
------------------------------------------------------------

**Cambia ahora a una terminal local en tu estación de trabajo con Fedora Linux.** Si abriste una pestaña nueva, exporta primero tu IP pública en ``IP_DEL_SERVIDOR``:

.. code-block:: bash

   export IP_DEL_SERVIDOR="203.0.113.15"

#. **Validación estricta de TLS con curl:**

   .. code-block:: bash

      curl -I "https://${IP_DEL_SERVIDOR}.sslip.io/"

   Observa que no se usa ``-k`` ni ``--insecure``. Recibirás ``HTTP/2 200`` con encabezado ``server: Rocket`` sobre TLS válido emitido por Let's Encrypt.

#. **Comprobación de bloqueo WAN en el puerto 8080:**

   .. code-block:: bash

      curl --connect-timeout 5 "http://${IP_DEL_SERVIDOR}:8080/"

   Esta petición debe fallar por tiempo agotado o conexión rechazada, confirmando que Vaultwarden permanece aislado en loopback y protegido por Firewalld.

#. **Acceso desde el navegador y creación de tu cuenta:** Abre ``https://${IP_DEL_SERVIDOR}.sslip.io`` en tu navegador sustituyendo ``${IP_DEL_SERVIDOR}`` por la IP de tu servidor. Verás una **conexión HTTPS verificada sin advertencias** desde el primer instante. Haz clic en **Crear cuenta**, define tu correo y contraseña maestra, e inicia sesión en tu bóveda privada.

#. **Inspección de registros JSON estructurados:** **De vuelta en tu sesión SSH del servidor remoto**, comprueba que Caddy escribe registros estructurados en ``/var/log/caddy`` sin errores de SELinux:

   .. code-block:: bash

      tail -n 5 /var/log/caddy/vaultwarden.access.log | jq .

Paso H: Mantenimiento Continuo y Actualizaciones Automáticas
------------------------------------------------------------

Continúa **en el servidor remoto vía SSH** para automatizar el parcheo del sistema operativo y la actualización del contenedor.

1. Actualizaciones del Sistema Operativo con ``dnf-automatic``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En CentOS Stream 10 con DNF5, ``/etc/dnf/automatic.conf`` puede no existir hasta copiar la plantilla base. Configúralo para aplicar actualizaciones diarias de forma desatendida:

.. code-block:: bash

   [[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
   sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
   systemctl --now enable dnf-automatic.timer

2. Actualizaciones Automáticas del Contenedor con Podman Quadlet
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Gracias a ``AutoUpdate=registry`` en ``vaultwarden.container``, Podman puede actualizar la imagen y reiniciar el servicio automáticamente con reversión integrada si el arranque falla:

.. code-block:: bash

   # Habilitar la revisión diaria automatizada
   systemctl --now enable podman-auto-update.timer

   # Ejecutar una comprobación manual bajo demanda
   podman auto-update

   # Limpiar capas huérfanas tras actualizaciones sucesivas
   podman image prune --force

3. Automatización Declarativa con OpenTofu e Infraestructura como Código
========================================================================

Ahora que dominas manualmente cada directiva, permiso y regla de SELinux, automatiza todo el despliegue **desde tu estación de trabajo con Fedora Linux** usando **OpenTofu** y la API de **Cherry Servers**.

.. warning::
   **Disciplina de costos:** Si creaste un servidor manual en la nube durante la Sección 2, destrúyelo desde el portal de Cherry Servers antes de desplegar esta instancia automatizada para evitar cobros duplicados.

Instalación de OpenTofu en tu Estación de Trabajo
-------------------------------------------------

Los manifiestos de este módulo requieren OpenTofu ``>= 1.8.0``. Si aún no lo instalaste en la Sección 1, instálalo y verifica su versión en Fedora Linux:

.. code-block:: bash

   sudo dnf -y install opentofu
   tofu version

Clonar el Repositorio y Explorar Manifiestos
--------------------------------------------

Clona el repositorio oficial de la serie e ingresa al directorio de OpenTofu del Cómo 02:

.. code-block:: bash

   git clone https://gitlab.com/renich/cherry-servers.git
   cd cherry-servers/02-caddy-podman/tofu

La estructura es **plana y transparente**, sin módulos anidados opacos:

* `tofu/provider.tf <tofu/provider.tf>`__: Declara ``required_version = ">= 1.8.0"`` y el proveedor ``cherryservers/cherryservers ~> 1.5.3``.
* `tofu/variables.tf <tofu/variables.tf>`__: Define ``region``, ``server_plan``, ``server_image``, ``ssh_public_key``, ``ssh_key_id``, ``vault_domain`` y ``enable_bootstrap``; con ``vault_domain = "auto"`` permite autogenerar ``${IP_DEL_SERVIDOR}.sslip.io`` con Let's Encrypt.
* `tofu/main.tf <tofu/main.tf>`__: Registra tu clave SSH o reutiliza ``ssh_key_id``, aprovisiona la instancia Cloud VPS e inyecta `scripts/bootstrap.bash <scripts/bootstrap.bash>`__.
* `tofu/outputs.tf <tofu/outputs.tf>`__: Muestra la IP pública, el dominio efectivo, la URL HTTPS y el comando SSH.
* `tofu/terraform.tfvars.example <tofu/terraform.tfvars.example>`__: Plantilla de variables para tus credenciales locales.

El Script de Arranque Declarativo ``scripts/bootstrap.bash``
------------------------------------------------------------

OpenTofu renderiza e inyecta `scripts/bootstrap.bash <scripts/bootstrap.bash>`__ codificado en Base64 dentro de ``user_data``:

.. code-block:: hcl

   resource "cherryservers_server" "caddy_node" {
     project_id    = var.project_id
     region        = var.region
     plan          = var.server_plan
     image         = var.server_image
     hostname      = var.server_name
     spot_instance = var.spot_instance
     ssh_key_ids   = [local.active_ssh_key_id]

     # Inyecta el script de arranque codificado en Base64 requerido por Cherry Servers si enable_bootstrap es true
     user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap.bash", {
       SERVER_NAME   = var.server_name
       VAULT_DOMAIN  = var.vault_domain
       TLS_DIRECTIVE = local.tls_directive
     })) : null

     tags = {
       Environment = "Lab"
       ManagedBy   = "OpenTofu"
       Series      = "Comos-Linux-FOSS"
       Service     = "Caddy-Vaultwarden"
     }
   }

Configurar Variables Locales y Desplegar con ``tofu apply``
-----------------------------------------------------------

Copia la plantilla local y restringe sus permisos inmediatamente; recuerda que ``terraform.tfvars`` contiene tu token privado y nunca debe subirse a Git:

.. code-block:: bash

   cp terraform.tfvars.example terraform.tfvars
   chmod 600 terraform.tfvars

**Dónde obtener cada variable antes de editar** ``terraform.tfvars`` **:**

* ``cherry_auth_token``: Genera un token personal en el `Portal de Cherry Servers, API Keys <https://portal.cherryservers.com/settings/api-keys>`__.
* ``project_id``: Abre el portal de Cherry Servers, ingresa a **Projects** y copia el ID numérico de tu proyecto.
* ``ssh_public_key``: Copia la salida completa de ``cat ~/.ssh/id_ed25519.pub`` en tu estación de trabajo.
* ``ssh_key_id``: Opcional; si ya subiste esa misma clave Ed25519 al portal en la práctica manual o en un Cómo previo, entra a **SSH Keys**, copia su ID numérico, descomenta ``ssh_key_id`` y deja ``ssh_public_key = ""`` para reutilizarla sin error de clave duplicada.
* ``region``: Código geográfico del centro de datos, por defecto ``LT-Siauliai``.

Completa ``terraform.tfvars`` con tus valores:

.. code-block:: hcl

   cherry_auth_token = "TU_API_TOKEN_DE_CHERRY_SERVERS"
   project_id        = 123456
   ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... tu_correo@ejemplo.com"
   # ssh_key_id      = "20003" # Descomenta si tu clave ya está registrada en Cherry Servers y deja ssh_public_key vacío
   region            = "LT-Siauliai"
   server_name       = "0.caddy.linenes.tld"
   vault_domain      = "auto" # "auto" asigna tu IP pública con .sslip.io y Let's Encrypt, o indica tu dominio propio
   server_image      = "centos_stream_10_64bit"
   spot_instance     = false
   # server_plan     = "B1-1-1gb-20s-shared" # Cloud VPS 1 por defecto (~$0.015 EUR/hr) o "B2-2-2gb-40s-shared" (Cloud VPS 2)
   # enable_bootstrap = true # Cambia a false si deseas aprovisionar la máquina vacía para la práctica manual

Inicializa el proveedor, valida la sintaxis, revisa el plan y despliega:

.. code-block:: bash

   tofu init
   tofu validate
   tofu plan
   tofu apply

Confirma escribiendo ``yes``. OpenTofu aprovisionará la máquina y mostrará tus salidas de conexión:

.. code-block:: text

   Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

   Outputs:

   server_ip = "203.0.113.15"
   ssh_command = "ssh root@203.0.113.15"
   vault_domain = "203.0.113.15.sslip.io"
   vaultwarden_url = "https://203.0.113.15.sslip.io"

.. warning::
   **Ejecución asíncrona de** ``user_data`` **:** ``tofu apply`` concluye en cuanto Cherry Servers enciende la VM, pero ``scripts/bootstrap.bash`` sigue ejecutándose en segundo plano dentro del servidor durante 1 a 3 minutos mientras instala paquetes RPM, descarga Vaultwarden, aplica SELinux y tramita el certificado TLS.

Sigue el progreso del arranque en tiempo real desde tu estación de trabajo:

.. code-block:: bash

   ssh "root@$(tofu output -raw server_ip)" "tail -f /var/log/user-data.log"

Cuando aparezca ``[+] Despliegue completado con éxito``, pulsa ``Ctrl+C`` y abre la URL reportada en ``vaultwarden_url`` para verificar tu bóveda con HTTPS oficial.

4. Destrucción del Servidor y Control de Costos
===============================================

Al terminar tu práctica, destruye la infraestructura desde ``02-caddy-podman/tofu`` en tu estación de trabajo para detener la facturación por hora y limpiar secretos locales.

Destrucción de la Infraestructura con OpenTofu
----------------------------------------------

Captura primero la IP asignada, destruye los recursos, elimina la huella SSH antigua de ``known_hosts``, borra el archivo local de credenciales y verifica que el estado quede vacío:

.. code-block:: bash

   IP_DEL_SERVIDOR=$(tofu output -raw server_ip)
   tofu destroy
   ssh-keygen -R "${IP_DEL_SERVIDOR}"
   rm -f terraform.tfvars
   tofu state list

Confirma la destrucción escribiendo ``yes``.

* Si registraste la clave mediante ``ssh_public_key``, OpenTofu destruirá ambos recursos, ``Resources: 2 destroyed``.
* Si reutilizaste una clave existente con ``ssh_key_id``, OpenTofu destruirá únicamente la máquina virtual, ``Resources: 1 destroyed``, preservando tu clave SSH intacta en Cherry Servers para futuros Cómos.
* El comando ``tofu state list`` debe devolver una salida vacía confirmando cero recursos activos.

El costo total de completar este laboratorio ronda entre **~$0.02 y $0.03 USD**.

Ciclo de Vida Criptográfico y Liberación del Dominio ``sslip.io``
-----------------------------------------------------------------

Al destruir entornos efímeros conviene comprender el ciclo de vida de los certificados TLS:

#. **Destrucción de la clave privada:** ``tofu destroy`` elimina la VM y su disco. La clave privada RSA/ECC que Caddy generó desaparece físicamente; sin ella, el certificado público emitido no puede reutilizarse y caducará a los 90 días.
#. **Liberación algorítmica de** ``sslip.io`` **:** Como ``sslip.io`` es un DNS sin estado, no requiere cancelar registros ni paneles; cuando Cherry Servers libera la IP, ninguna petición posterior alcanza tus datos.

.. note::
   **Revocación activa ante compromiso real:** Si en un entorno de producción sospechas filtración de la clave privada antes de destruir el nodo, revoca el certificado por SSH desde el servidor remoto:

   .. code-block:: bash

      dnf -y install certbot
      IP_PUBLICA=$(curl -fs4 --connect-timeout 5 --max-time 10 https://icanhazip.com || ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 !~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
      if [[ -n "${IP_PUBLICA}" ]]; then
        DOMINIO_VAULT="${IP_PUBLICA}.sslip.io"
        certbot revoke \
          --cert-path "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMINIO_VAULT}/${DOMINIO_VAULT}.crt" \
          --key-path "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMINIO_VAULT}/${DOMINIO_VAULT}.key" \
          --reason cessationOfOperation \
          --no-delete-after-revoke \
          --non-interactive
      fi

5. Retos de Aprendizaje y Práctica
==================================

Para afianzar tu dominio de Podman Quadlets, Caddy y SELinux, resuelve estos 3 desafíos sin solución guiada:

#. **Reto 1: Blindar Vaultwarden deshabilitando registros públicos y protegiendo** ``/admin``

   * **Objetivo:** Cierra el registro abierto de nuevas cuentas tras crear la tuya y habilita el panel administrativo en ``https://${IP_DEL_SERVIDOR}.sslip.io/admin`` utilizando **tokens derivados con Argon2id** en lugar de una contraseña en texto plano.
   * **Advertencia de seguridad:** Nunca coloques ``ADMIN_TOKEN`` directamente dentro de ``/etc/containers/systemd/vaultwarden.container``, ya que ese archivo tiene permisos ``0644`` legibles por cualquier usuario local del sistema. Investiga e implementa la inyección segura del secreto mediante ``podman secret`` con la directiva ``Secret=`` de Quadlet, o bien mediante un archivo aislado con permisos ``0600`` cargado con ``EnvironmentFile=``.
   * **Criterio de éxito:** El formulario público de registro rechaza nuevas cuentas, ``/admin`` valida correctamente tu token Argon2id, ``stat`` confirma que ningún usuario sin privilegios puede leer el secreto y ``ausearch -m AVC,USER_AVC -ts recent`` no reporta denegaciones.

#. **Reto 2: Publicar un segundo servicio virtual con Caddy y** ``sslip.io`` **en modo multi-sitio SNI**

   * **Objetivo:** Despliega un segundo contenedor independiente gestionado por Podman Quadlet enlazado únicamente a loopback en otro puerto local, por ejemplo ``127.0.0.1:8081``, y publícalo mediante un segundo bloque en ``/etc/caddy/Caddyfile`` bajo el subdominio ``web.${IP_DEL_SERVIDOR}.sslip.io``, validando la configuración como usuario ``caddy`` antes de recargar el servicio.
   * **Criterio de éxito:** Tanto ``https://${IP_DEL_SERVIDOR}.sslip.io`` como ``https://web.${IP_DEL_SERVIDOR}.sslip.io`` responden simultáneamente por los puertos ``80`` y ``443`` con certificados independientes de Let's Encrypt, el nuevo puerto local permanece inaccesible desde internet y SELinux continúa en Enforcing sin AVCs.

#. **Reto 3: Portar la configuración manual a Debian 13 o Ubuntu 26.04 LTS**

   * **Objetivo:** Reproduce el despliegue manual de Caddy y Podman Quadlet sobre **Debian 13** o **Ubuntu 26.04 LTS**, documentando las diferencias reales frente a CentOS Stream 10 en gestor de paquetes APT, repositorios de Caddy, cortafuegos y el paso de SELinux a AppArmor, donde no aplican ``:Z`` ni ``httpd_can_network_connect``.
   * **Criterio de éxito:** Vaultwarden funciona tras Caddy con TLS válido de Let's Encrypt, el puerto ``8080`` queda restringido a loopback y las reglas del cortafuegos bloquean accesos externos no autorizados.

Referencias Oficiales
=====================

* `CentOS Stream: proyecto oficial <https://www.centos.org/centos-stream/>`__
* `EPEL: Extra Packages for Enterprise Linux <https://docs.fedoraproject.org/en-US/epel/>`__
* `Podman Quadlet: referencia de podman-systemd.unit <https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html>`__
* `Caddy: documentación oficial de Caddyfile <https://caddyserver.com/docs/caddyfile>`__
* `Vaultwarden: Wiki oficial <https://github.com/dani-garcia/vaultwarden/wiki>`__
* `sslip.io: servicio DNS comodín sin estado <https://sslip.io/>`__
* `Red Hat Enterprise Linux 10: Using SELinux <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/secure-getting_started_with_selinux>`__
* `OpenTofu: documentación oficial <https://opentofu.org/docs/>`__

Dudas y Preguntas
=================

¿Tienes preguntas sobre Podman Quadlets, configuración de Caddy o políticas de SELinux? Abre un ticket en `Issues del repositorio en GitLab <https://gitlab.com/renich/cherry-servers/-/issues>`__ o súmate a las conversaciones de la comunidad. Continúa tu aprendizaje en el `Cómo 03: Reconstrucción y Automatización con Ansible <../03-ansible/README.rst>`__.

Licencia
========

Este documento y el material educativo de este Cómo se distribuyen bajo los términos de la **GNU Free Documentation License**, GFDL Versión 1.3 o cualquier versión posterior publicada por la Free Software Foundation; sin secciones invariantes ni textos de portada o contraportada.

Consulta el archivo `LICENSE <../LICENSE>`__ en la raíz del repositorio para leer los términos completos.
