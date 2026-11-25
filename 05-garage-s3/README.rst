===========================================================================
Cómo desplegar Almacenamiento S3 Distribuido con Garage en CentOS Stream 10
===========================================================================

:Módulo: Cómo 05: Almacenamiento S3 Distribuido con Garage
:Versión: ``v1.0.0``
:Fecha: ``2026-11-24``
:Directorio: `05-garage-s3 <https://gitlab.com/renich/cherry-servers/-/tree/master/05-garage-s3>`__
:Licencia: `GFDL-1.3-or-later <../LICENSE>`__
:Tipo de instancia: 3x Cloud VPS 1, ``B1-1-1gb-20s-shared``
:Costo por hora: ~$0.045 EUR/hora
:Tiempo promedio: 3 horas
:Gasto estimado total: ~$0.14 USD

¡Hola! 👋

Te doy la bienvenida al **Cómo 05** de nuestra serie práctica de infraestructura empresarial en Linux para la comunidad de software libre. En los laboratorios anteriores construiste servicios en un solo nodo y levantaste tus tres primitivas de red y almacenamiento en el Cómo 04: DNS autoritativo, NTP y NFSv4.2 sobre VLAN privada. Hoy das el salto hacia almacenamiento de objetos S3 distribuido, tolerante a fallos y sin puntos únicos de coordinación con **Garage v2.6.0**.

En lugar de instalar software pesado sobre máquinas sobredimensionadas, desplegarás un clúster Garage de 3 nodos distribuidos en tres zonas de disponibilidad lógicas ``z1``, ``z2`` y ``z3`` sobre instancias **CentOS Stream 10** ligeras en **Cherry Servers**, respetando estrictamente **SELinux en modo Enforcing**, etiquetas **MCS** de Podman Quadlets, aislamiento de red entre las zonas ``public`` e ``internal`` de Firewalld, jerarquía **FHS 3.0** bajo ``/srv/garage``, terminación HTTPS automática con **Caddy** y **Let's Encrypt** mediante ``sslip.io``, y nuestra regla pedagógica de oro: **manual primero, automatización después**.

1. Prerrequisitos del Laboratorio
=================================

#. **Tres servidores con CentOS Stream 10 en Cherry Servers**, enlazados por VLAN privada RFC 1918 y con acceso SSH como ``root`` exclusivamente mediante clave pública Ed25519 en ``~/.ssh/id_ed25519.pub``.

   * **Saldo promocional de $20 USD:** Si todavía no tienes cuenta, regístrate en `este enlace de bienvenida de Cherry Servers <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__ usando el código ``LinuxEnEspanol`` para recibir **$20 USD de crédito** y cubrir este laboratorio prácticamente sin costo.

#. **Herramientas locales en tu estación de trabajo con Fedora Linux:**

   .. code-block:: bash

      sudo dnf -y install openssh-clients git-core curl jq rclone opentofu

2. Construcción y Configuración Manual vía SSH, El Núcleo del Aprendizaje
=========================================================================

Despliega tres instancias ``Cloud VPS 1`` con CentOS Stream 10 y anota sus direcciones IP públicas y privadas asignadas a la misma VLAN. Luego abre una sesión SSH directa hacia cada nodo con tu clave Ed25519:

.. code-block:: bash

   ssh "root@${IP_PUBLICA_NODO_0}"
   ssh "root@${IP_PUBLICA_NODO_1}"
   ssh "root@${IP_PUBLICA_NODO_2}"

Paso A: Nombre de Host, Red Privada y Repositorios EPEL 10
----------------------------------------------------------

En cada servidor, define el FQDN interno y verifica la dirección IPv4 privada RFC 1918 asignada a la interfaz de red de VLAN:

.. code-block:: bash

   # En Nodo 0, Nodo 1 y Nodo 2 cambia el índice inicial 0, 1 o 2 según corresponda
   hostnamectl set-hostname "0.garage.linenes.tld"
   ip -4 -o addr show scope global

Anota las direcciones privadas de tu VLAN privada, por ejemplo ``10.202.8.5`` en el Nodo 0, ``10.202.8.49`` en el Nodo 1 y ``10.202.8.12`` en el Nodo 2, además de la IP pública del Nodo 0.

Activa **EPEL 10** y el repositorio **CRB** en los tres nodos e instala Podman, Firewalld y utilidades base. En el **Nodo 0** añade ``caddy`` para la puerta de enlace HTTPS:

.. code-block:: bash

   # En los tres nodos
   dnf -y install epel-release
   /usr/bin/crb enable
   dnf -y install podman firewalld jq curl dnf-automatic policycoreutils-python-utils

   # Adicionalmente solo en Nodo 0
   dnf -y install caddy

Paso B: Segmentación de Firewalld entre ``public`` e ``internal``
-----------------------------------------------------------------

Antes de iniciar ningún contenedor ni abrir el proxy inverso, habilita ``firewalld`` y aísla los puertos de clúster ``3900`` S3 API, ``3901`` RPC entre nodos, ``3902`` S3 Web y ``3903`` Admin API dentro de la zona ``internal`` asociada a los rangos RFC 1918. Así evitas exponer puertos administrativos y el puerto ``3903`` a internet:

.. code-block:: bash

   systemctl --now enable firewalld

   # En los tres nodos: restringe tráfico de clúster a redes privadas RFC 1918
   firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
   firewall-cmd --permanent --zone=internal --add-source=192.168.0.0/16
   firewall-cmd --permanent --zone=internal --add-source=172.16.0.0/12
   firewall-cmd --permanent --zone=internal --add-port=3900/tcp
   firewall-cmd --permanent --zone=internal --add-port=3901/tcp
   firewall-cmd --permanent --zone=internal --add-port=3902/tcp
   firewall-cmd --permanent --zone=internal --add-port=3903/tcp

   # Solo en Nodo 0: habilita HTTP y HTTPS públicos para Caddy y ACME de Let's Encrypt
   firewall-cmd --permanent --zone=public --add-service=http
   firewall-cmd --permanent --zone=public --add-service=https

   firewall-cmd --reload
   firewall-cmd --get-active-zones

Paso C: Estructura FHS 3.0 y Configuración de Garage ``v2.6.0``
---------------------------------------------------------------

Siguiendo **FHS 3.0**, separa los metadatos y bloques de objetos bajo ``/srv/garage`` y los archivos de configuración bajo ``/etc/garage``. Primero genera en el Nodo 0 dos secretos criptográficos de 256 bits para compartirlos entre los tres nodos del clúster:

.. code-block:: bash

   # Ejecuta en Nodo 0 y guarda ambos valores de forma segura para los tres nodos
   RPC_SECRET=$(openssl rand -hex 32)
   ADMIN_TOKEN=$(openssl rand -hex 32)

Crea los directorios en los tres nodos con permisos restrictivos ``0750`` y genera ``/etc/garage/garage.toml`` bajo ``umask 027`` para evitar que otros usuarios lean los secretos:

.. code-block:: bash

   mkdir -p /srv/garage/{meta,data} /etc/garage /etc/containers/systemd
   chmod 750 /srv/garage /srv/garage/meta /srv/garage/data /etc/garage

   umask 027
   cat << EOF > /etc/garage/garage.toml
   metadata_dir = "/var/lib/garage/meta"
   data_dir = "/var/lib/garage/data"
   db_engine = "sqlite"

   replication_factor = 3
   consistency_mode = "consistent"

   rpc_bind_addr = "[::]:3901"
   rpc_public_addr = "${PRIV_IP_NODO}:3901"
   rpc_secret = "${RPC_SECRET}"
   allow_world_readable_secrets = false

   [s3_api]
   s3_region = "garage"
   api_bind_addr = "[::]:3900"
   root_domain = ".s3.linenes.tld"

   [s3_web]
   bind_addr = "[::]:3902"
   root_domain = ".web.linenes.tld"
   index = "index.html"

   [admin]
   api_bind_addr = "[::]:3903"
   admin_token = "${ADMIN_TOKEN}"
   EOF
   umask 022
   chown root:root /etc/garage/garage.toml
   chmod 640 /etc/garage/garage.toml

.. important::

   La imagen ``docker.io/dxflrs/garage:v2.6.0`` es un binario estático construido con ``FROM scratch``, por lo que no incluye intérprete ``/bin/sh`` en su interior. Toda administración del clúster se realiza mediante ``podman exec garage /garage ...``. Además, **nunca ejecutes** ``restorecon -Rv /srv/garage`` cuando uses volúmenes con sufijo ``:Z``, ya que Podman asigna categorías MCS únicas de ``container_file_t`` por contenedor y ``restorecon`` revertiría el etiquetado a ``var_t``.

Paso D: Podman Quadlet en Systemd y Malla de 3 Nodos
----------------------------------------------------

En lugar de scripts frágiles con ``podman run``, declara la unidad nativa **Podman Quadlet** en ``/etc/containers/systemd/garage.container`` en los tres nodos, enlazando los puertos únicamente a ``127.0.0.1`` y a ``${PRIV_IP_NODO}`` de cada servidor:

.. code-block:: ini

   [Unit]
   Description=Garage Distributed S3 Storage v2.6.0
   Documentation=https://garagehq.deuxfleurs.fr/
   After=network-online.target firewalld.service
   Wants=network-online.target

   [Container]
   Image=docker.io/dxflrs/garage:v2.6.0
   ContainerName=garage
   HostName=0.garage.linenes.tld
   PublishPort=127.0.0.1:3900:3900
   PublishPort=${PRIV_IP_NODO}:3900:3900
   PublishPort=127.0.0.1:3901:3901
   PublishPort=${PRIV_IP_NODO}:3901:3901
   PublishPort=127.0.0.1:3902:3902
   PublishPort=${PRIV_IP_NODO}:3902:3902
   PublishPort=127.0.0.1:3903:3903
   PublishPort=${PRIV_IP_NODO}:3903:3903
   Volume=/srv/garage/meta:/var/lib/garage/meta:Z
   Volume=/srv/garage/data:/var/lib/garage/data:Z
   Volume=/etc/garage/garage.toml:/etc/garage.toml:ro,Z
   Environment=RUST_LOG=garage=info
   AutoUpdate=registry

   [Service]
   Restart=on-failure
   TimeoutStartSec=180

   [Install]
   WantedBy=multi-user.target default.target

Ajusta ``HostName=`` en el Nodo 1 y el Nodo 2 a ``1.garage.linenes.tld`` y ``2.garage.linenes.tld``, luego recarga systemd y arranca Garage junto con el temporizador de actualizaciones automáticas de contenedores:

.. code-block:: bash

   chmod 644 /etc/containers/systemd/garage.container
   systemctl daemon-reload
   systemctl start garage.service
   systemctl --now enable podman-auto-update.timer

Ahora conecta el **Nodo 1** y el **Nodo 2** con el **Nodo 0** usando la API de administración privada sobre la VLAN:

.. code-block:: bash

   # Ejecuta en Nodo 1 y Nodo 2 sustituyendo ADMIN_TOKEN y PRIV_IP_NODO_0
   NODE0_ID=$(curl -fsS --connect-timeout 5 --max-time 10 \
     -H "Authorization: Bearer ${ADMIN_TOKEN}" \
     "http://${PRIV_IP_NODO_0}:3903/v2/GetClusterStatus" | jq -r --arg ip "${PRIV_IP_NODO_0}" '.nodes[] | select(.isUp == true and ((.addr // "") | startswith($ip + ":"))) | .id' | head -n1)
   podman exec garage /garage node connect "${NODE0_ID}@${PRIV_IP_NODO_0}:3901"

Paso E: Topología de 3 Zonas, Bucket S3 y Llaves de Acceso
----------------------------------------------------------

Verifica en el **Nodo 0** que los tres nodos aparezcan conectados y asigna cada uno a su zona de disponibilidad independiente ``z1``, ``z2`` y ``z3`` con capacidad declarada de ``10G``:

.. code-block:: bash

   podman exec garage /garage status
   podman exec garage /garage layout assign "${ID_NODO_0}" -z z1 -c 10G -t 0.garage.linenes.tld
   podman exec garage /garage layout assign "${ID_NODO_1}" -z z2 -c 10G -t 1.garage.linenes.tld
   podman exec garage /garage layout assign "${ID_NODO_2}" -z z3 -c 10G -t 2.garage.linenes.tld
   podman exec garage /garage layout apply --version 1

Salida real esperada tras aplicar la topología ``v1`` en Garage:

.. code-block:: text

   ==== HEALTHY NODES ====
   ID                Hostname              Address           Tags                    Zone  Capacity  DataAvail         ResyncQueue  Version
   16c4201ec4d318bc  0.garage.linenes.tld  10.202.8.5:3901   [0.garage.linenes.tld]  z1    9.3 GiB   18.0 GiB (90.5%)  0            v2.6.0
   a2de11f79ad106fc  2.garage.linenes.tld  10.202.8.12:3901  [2.garage.linenes.tld]  z3    9.3 GiB   18.1 GiB (90.8%)  0            v2.6.0
   f53947e52d1a681f  1.garage.linenes.tld  10.202.8.49:3901  [1.garage.linenes.tld]  z2    9.3 GiB   18.1 GiB (90.8%)  0            v2.6.0

Crea ahora el bucket ``sitio``, habilita el servidor web estático sobre HTTP interno y genera una llave S3 con permisos completos de lectura, escritura y propiedad sobre dicho bucket, exportando ``accessKeyId`` y ``secretAccessKey`` desde el JSON resultante para el resto de la práctica:

.. code-block:: bash

   podman exec garage /garage bucket create sitio
   podman exec garage /garage bucket website --allow sitio
   podman exec garage /garage json-api CreateKey '{"name":"lab-key"}' | jq .

   # Exporta ambos valores devueltos por CreateKey antes de asignar permisos o usar rclone
   export AWS_ACCESS_KEY_ID="${ACCESS_KEY_ID_GENERADA}"
   export AWS_SECRET_ACCESS_KEY="${SECRET_ACCESS_KEY_GENERADA}"

   podman exec garage /garage bucket allow --read --write --owner sitio --key "${AWS_ACCESS_KEY_ID}"

Paso F: Puerta de Enlace HTTPS con Caddy y SELinux en Modo Enforcing
--------------------------------------------------------------------

En **CentOS Stream 10** con **EPEL 10**, el paquete oficial de ``caddy`` registra contextos SELinux para ``/etc/caddy`` como ``httpd_config_t`` y ``/var/lib/caddy`` como ``httpd_var_lib_t``, pero no define una regla por defecto para ``/var/log/caddy``. Si creas bitácoras en esa ruta bajo ``var_log_t`` o validas la configuración como ``root``, SELinux en modo **Enforcing** bloqueará a ``httpd_t`` al arrancar el servicio ``caddy``.

Para resolverlo de raíz sin deshabilitar SELinux, registra la regla persistente ``httpd_log_t``, habilita el booleano ``httpd_can_network_connect`` para que Caddy alcance los tres servidores en la VLAN privada y valida siempre bajo el usuario ``caddy`` con ``runuser``:

.. code-block:: bash

   mkdir -p /etc/caddy /var/log/caddy
   cat << EOF > /etc/caddy/Caddyfile
   s3.${IP_PUBLICA_NODO_0}.sslip.io {
       reverse_proxy ${PRIV_IP_NODO_0}:3900 ${PRIV_IP_NODO_1}:3900 ${PRIV_IP_NODO_2}:3900 {
           fail_duration 10s
           lb_try_duration 5s
       }

       log {
           output file /var/log/caddy/garage-s3.access.log
           format json
       }
   }

   web.${IP_PUBLICA_NODO_0}.sslip.io {
       reverse_proxy ${PRIV_IP_NODO_0}:3902 ${PRIV_IP_NODO_1}:3902 ${PRIV_IP_NODO_2}:3902 {
           fail_duration 10s
           lb_try_duration 5s
           header_up Host sitio.web.linenes.tld
       }

       log {
           output file /var/log/caddy/garage-web.access.log
           format json
       }
   }
   EOF

   caddy fmt --overwrite /etc/caddy/Caddyfile
   chown -R caddy:caddy /etc/caddy /var/log/caddy
   chmod 750 /var/log/caddy
   chmod 640 /etc/caddy/Caddyfile
   semanage fcontext -a -t httpd_log_t '/var/log/caddy(/.*)?'
   setsebool -P httpd_can_network_connect 1
   restorecon -Rv /etc/caddy /var/log/caddy
   runuser -u caddy -- caddy validate --config /etc/caddy/Caddyfile
   restorecon -Rv /etc/caddy /var/log/caddy
   systemctl --now enable caddy.service

En pocos segundos, Caddy resolverá ambos subdominios ``sslip.io``, completará el reto **TLS-ALPN-01** con **Let's Encrypt** y balanceará tus peticiones S3 y web hacia los tres nodos detrás del firewall.

Paso G: Pruebas Funcionales con ``rclone``, Integridad SHA-256 y Prueba de Caos
-------------------------------------------------------------------------------

Primero comprueba desde tu estación Fedora Linux que los tres servidores mantengan **SELinux Enforcing**, cero denegaciones **AVC** recientes, los puertos ``3900`` al ``3903`` cerrados desde internet y las ``256`` particiones saludables:

.. code-block:: bash

   # Desde tu estación de trabajo: confirma bloqueo WAN de puertos Garage
   for puerto in 3900 3901 3902 3903; do
     timeout 2 bash -c "exec 3<>/dev/tcp/${IP_PUBLICA_NODO_0}/${puerto}" && echo "ABIERTO" || echo "BLOQUEADO ${puerto}"
   done

   # En cada nodo por SSH: auditoría SELinux sin lectura bloqueante en stdin
   ssh -n "root@${IP_PUBLICA_NODO_0}" "getenforce && ausearch -m AVC,USER_AVC -ts recent </dev/null || true"
   ssh -n "root@${IP_PUBLICA_NODO_0}" "podman exec garage /garage json-api GetClusterHealth | jq ."

Ahora prueba la API S3 autenticada con **TLS estricto** usando variables de entorno en ``rclone``, sin almacenar secretos en texto claro dentro de archivos persistentes de configuración:

.. code-block:: bash

   export RCLONE_S3_PROVIDER=Other
   export RCLONE_S3_ENDPOINT="https://s3.${IP_PUBLICA_NODO_0}.sslip.io"
   export RCLONE_S3_REGION=garage
   export RCLONE_S3_FORCE_PATH_STYLE=true
   export RCLONE_S3_ENV_AUTH=false
   export RCLONE_S3_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
   export RCLONE_S3_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"

   cat << 'EOF' > index.html
   <!DOCTYPE html>
   <html lang="es">
   <head><meta charset="utf-8"><title>Cómo 05 Garage S3</title></head>
   <body><h1>Garage v2.6.0 en CentOS Stream 10: Quórum 3/3 Verificado</h1></body>
   </html>
   EOF
   dd if=/dev/urandom of=test-1m.bin bs=1M count=1 status=none
   sha256sum test-1m.bin

   rclone copyto index.html :s3:sitio/index.html
   rclone copyto test-1m.bin :s3:sitio/test-1m.bin
   rclone ls :s3:sitio
   curl -fsS --connect-timeout 5 --max-time 15 "https://web.${IP_PUBLICA_NODO_0}.sslip.io/"

   rclone copyto :s3:sitio/test-1m.bin downloaded-1m.bin
   sha256sum downloaded-1m.bin

Llegó el momento de comprobar la tolerancia real a fallos mediante una **Prueba de Caos** en vivo. Detén el servicio ``garage`` en el **Nodo 2**, verifica que el clúster pasa a estado ``degraded`` conservando quórum en ``2`` de ``3`` nodos, lee ``test-1m.bin`` y escribe un nuevo objeto durante la caída; luego arranca de nuevo el Nodo 2 y observa la recuperación automática:

.. code-block:: bash

   # 1. Simula la caída del Nodo 2
   ssh -n "root@${IP_PUBLICA_NODO_2}" "systemctl stop garage.service"
   ssh -n "root@${IP_PUBLICA_NODO_0}" "podman exec garage /garage json-api GetClusterHealth | jq ."

   # 2. Lectura web, lectura binaria y escritura nueva en quórum 2/3
   curl -fsS --connect-timeout 5 --max-time 10 "https://web.${IP_PUBLICA_NODO_0}.sslip.io/" >/dev/null && echo "Sitio web operativo con 2/3 nodos"
   echo "escritura-bajo-fallo-nodo2" > quorum-proof.txt
   rclone copyto quorum-proof.txt :s3:sitio/quorum-proof.txt

   # 3. Auto-sanación al restaurar el Nodo 2 tras unos segundos de resincronización RPC
   ssh -n "root@${IP_PUBLICA_NODO_2}" "systemctl start garage.service"
   sleep 5
   ssh -n "root@${IP_PUBLICA_NODO_0}" "podman exec garage /garage json-api GetClusterHealth | jq ."
   rclone copyto :s3:sitio/quorum-proof.txt quorum-verificado.txt
   sha256sum quorum-proof.txt quorum-verificado.txt

Estado degradado observado en ``GetClusterHealth`` durante la caída controlada del Nodo 2, manteniendo las ``256`` particiones en quórum:

.. code-block:: json

   {
     "connectedNodes": 2,
     "knownNodes": 3,
     "partitions": 256,
     "partitionsAllOk": 0,
     "partitionsQuorum": 256,
     "status": "degraded",
     "storageNodes": 3,
     "storageNodesUp": 2
   }

Estado saludable observado en ``GetClusterHealth`` tras reiniciar el Nodo 2 y completar la auto-sanación:

.. code-block:: json

   {
     "connectedNodes": 3,
     "knownNodes": 3,
     "partitions": 256,
     "partitionsAllOk": 256,
     "partitionsQuorum": 256,
     "status": "healthy",
     "storageNodes": 3,
     "storageNodesUp": 3
   }

Paso H: Mantenimiento Continuo y Actualizaciones
------------------------------------------------

Activa las actualizaciones automáticas de paquetes en **DNF5** cuidando el archivo ``%ghost`` en ``/etc/dnf/automatic.conf`` en los tres nodos, además de supervisar el temporizador de Podman:

.. code-block:: bash

   [[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
   sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
   systemctl --now enable dnf-automatic.timer
   systemctl --no-pager status podman-auto-update.timer dnf-automatic.timer

3. Automatización Declarativa con OpenTofu e Infraestructura como Código
========================================================================

Ahora que dominas la topología interna de Garage, las zonas de Firewalld, los volúmenes ``:Z`` y el contexto ``httpd_log_t`` de Caddy bajo SELinux Enforcing, consolida toda la arquitectura en código reproducible usando **OpenTofu** y los manifiestos de este módulo.

Clonar el Repositorio y Explorar Manifiestos
--------------------------------------------

.. code-block:: bash

   git clone https://gitlab.com/renich/cherry-servers.git
   cd "cherry-servers/05-garage-s3/tofu"

Estructura del módulo en ``05-garage-s3``:

* `tofu/provider.tf <tofu/provider.tf>`__: fija OpenTofu ``>= 1.8.0``, el proveedor ``cherryservers/cherryservers ~> 1.5.3`` y ``hashicorp/random ~> 3.6``.
* `tofu/variables.tf <tofu/variables.tf>`__: expone región, plan ``B1-1-1gb-20s-shared``, versión de imagen, nombres DNS internos ``0.garage.linenes.tld`` a ``2.garage.linenes.tld``, soporte para reutilizar una llave SSH ya registrada mediante ``ssh_key_id`` y bandera ``spot_instance``.
* `tofu/main.tf <tofu/main.tf>`__: genera secretos efímeros con ``random_id``, gestiona la llave SSH condicional con precondición de validación, aprovisiona primero el Nodo 0 con `scripts/bootstrap-node0.bash <scripts/bootstrap-node0.bash>`__ e inyecta la IP privada del Nodo 0 en los Nodos 1 y 2 mediante `scripts/bootstrap-peer.bash <scripts/bootstrap-peer.bash>`__.
* `tofu/outputs.tf <tofu/outputs.tf>`__: publica IPs públicas y privadas, accesos SSH, endpoints HTTPS de S3 y web y el comando exacto para leer tus credenciales generadas.

Funcionamiento del Aprovisionamiento Asíncrono
----------------------------------------------

El script del Nodo 0 instala y habilita la unidad systemd ``garage-cluster-init.service``, que espera en segundo plano a que los nodos pares completen la conexión TCP por la VLAN privada, aplica automáticamente la topología de 3 zonas ``z1``, ``z2`` y ``z3``, crea el bucket ``sitio`` con acceso web habilitado, genera la llave ``lab-key`` en ``/root/garage-credentials.txt`` con modo ``0600`` y actualiza ``/etc/caddy/Caddyfile`` para balancear entre los tres nodos.

.. note::

   En instancias **Cloud VPS con CentOS Stream 10** de Cherry Servers, ``cloud-init status`` transiciona a estado ``disabled`` al concluir la fase inicial. Inspecciona siempre el progreso real mediante ``tail -f /var/log/user-data.log`` en cada nodo y ``journalctl -u garage-cluster-init -n 50 --no-pager`` en el Nodo 0.

Configurar Variables Locales y Desplegar con ``tofu apply``
-----------------------------------------------------------

Si tu clave pública Ed25519 ya existe en Cherry Servers, evita el error de clave duplicada definiendo su identificador en ``ssh_key_id`` dentro de ``terraform.tfvars``. En caso contrario, deja ``ssh_key_id`` comentado y provee ``ssh_public_key``:

.. code-block:: bash

   cp terraform.tfvars.example terraform.tfvars
   chmod 600 terraform.tfvars

   # Edita terraform.tfvars con tu cherry_auth_token, project_id y ssh_public_key o ssh_key_id
   tofu init
   tofu validate
   tofu apply

Una vez completado el despliegue, consulta las salidas de endpoints HTTPS y credenciales iniciales:

.. code-block:: bash

   tofu output
   eval "$(tofu output -raw credentials_command)"

4. Destrucción del Servidor y Control de Costos
===============================================

Al terminar tus experimentos y pruebas con objetos S3, elimina por completo los tres servidores y los recursos generados para evitar cargos continuos:

.. code-block:: bash

   tofu destroy
   rm -f terraform.tfvars
   tofu state list

5. Retos de Aprendizaje y Práctica
==================================

Pon a prueba tu criterio operativo completando estos tres ejercicios sin soluciones prefabricadas:

#. **Reto 1: Dominio propio y múltiples buckets web detrás de Caddy**

   * **Objetivo:** Reemplaza los subdominios temporales ``sslip.io`` por registros ``A`` y ``CNAME`` bajo un dominio DNS real que controles, configurando un segundo bucket público servido desde ``static.tudominio.tld`` mediante otro bloque en ``/etc/caddy/Caddyfile``.
   * **Criterio de éxito:** Ambos sitios responden con certificado TLS válido de Let's Encrypt, ``caddy validate`` pasa bajo el usuario ``caddy`` y ``ausearch -m AVC,USER_AVC -ts recent`` muestra cero denegaciones.

#. **Reto 2: Expansión dinámica del clúster con un cuarto nodo y migración segura**

   * **Objetivo:** Despliega una cuarta instancia CentOS Stream 10 dentro de la misma VLAN privada, conéctala a la malla y agrégala al layout en una zona ``z4`` aplicando la transición de versión siguiente en Garage sin interrumpir lecturas sobre ``sitio``.
   * **Criterio de éxito:** ``podman exec garage /garage status`` lista los cuatro nodos activos con sus zonas asignadas, ``ResyncQueue`` llega a ``0`` en todos y el checksum ``sha256sum`` de ``test-1m.bin`` permanece intacto.

#. **Reto 3: Portabilidad a Debian 13 o Ubuntu LTS**

   * **Objetivo:** Reproduce manualmente la topología de 3 nodos y el proxy inverso TLS sobre **Debian 13** o **Ubuntu Server 24.04 LTS**, adaptando gestor de paquetes ``apt``, cortafuegos ``nftables`` o ``ufw`` y perfiles **AppArmor** en reemplazo de **SELinux Enforcing**.
   * **Criterio de éxito:** El clúster alcanza quórum sano de 256 particiones, los puertos internos ``3900`` a ``3903`` quedan bloqueados desde internet y ``rclone`` transfiere archivos con validación TLS estricta.

Dudas y Preguntas
-----------------

¿Encontraste algún detalle técnico, tienes una mejora para el módulo o quieres compartir tus resultados del quórum distribuido? Abre un ticket en el repositorio oficial: `Reportar un issue en GitLab <https://gitlab.com/renich/cherry-servers/-/issues>`__.

Licencia
========

Esta guía está publicada bajo la **Licencia de Documentación Libre GNU v1.3 o posterior**, `GFDL-1.3-or-later <../LICENSE>`__. Los scripts y manifiestos de infraestructura incluidos siguen las condiciones indicadas en la raíz del repositorio.
