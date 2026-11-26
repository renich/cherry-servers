===========================================================================
Cómo desplegar Almacenamiento S3 Distribuido con Garage en CentOS Stream 10
===========================================================================

:Módulo: Cómo 05: Almacenamiento S3 Distribuido con Garage
:Versión: ``v1.0.0``
:Fecha: ``2026-11-24``
:Directorio: `05-garage-s3 <https://gitlab.com/renich/cherry-servers/-/tree/master/05-garage-s3>`__
:Licencia: `GFDL-1.3-or-later <../LICENSE>`__
:Tipo de instancia: 3x Cloud VPS 1, ``B1-1-1gb-20s-shared``, con 1 vCore, 1 GB RAM y 20 GB SSD por nodo
:Costo por hora: ~$0.045 EUR/hora, ~$0.05 USD/hora por los tres nodos
:Tiempo promedio: 3 horas
:Gasto estimado total: ~$0.14 USD

¡Hola! 👋

Te doy la bienvenida al **Cómo 05** de nuestra serie práctica de infraestructura empresarial en Linux para la comunidad de software libre. En los tres primeros módulos desplegaste servicios sobre un solo nodo y en el **Cómo 04** levantaste tus tres primitivas internas de red y almacenamiento sobre VLAN privada: DNS autoritativo con BIND 9, tiempo de precisión con Chrony y archivos compartidos con NFSv4.2. Hoy das el siguiente paso lógico hacia el **almacenamiento de objetos S3 distribuido y tolerante a fallos** con **Garage v2.6.0**.

Conviene distinguir con claridad cuándo usar cada modelo. Mientras **NFSv4.2** del Cómo 04 expone un sistema de archivos jerárquico POSIX montado desde un servidor concreto, el **almacenamiento de objetos S3** gestiona objetos inmutables identificados por *bucket* y clave sobre HTTP/HTTPS con firmas criptográficas **SigV4**, replicación horizontal nativa y publicación web directa. En lugar de montar sistemas pesados que exigen decenas de gigabytes de memoria, construirás un clúster **Garage** sobre tres servidores ligeros:

* **Sin nodo maestro ni punto único de coordinación:** Garage opera como una malla entre pares basada en **CRDTs**, estructuras de datos replicadas libres de conflictos, que reparten los datos sobre un anillo de *hashing* consistente dividido en **256 particiones**.
* **Motor ligero para 1 GB de RAM:** Al fijar ``db_engine = "sqlite"``, cada nodo conserva un consumo mínimo de memoria y disco, ideal para servidores VPS modestos o despliegues en el borde.
* **Quórum real 2/3 entre tres zonas:** Con ``replication_factor = 3`` y ``consistency_mode = "consistent"`` repartidos entre las zonas lógicas ``z1``, ``z2`` y ``z3``, cada lectura y escritura exige mayoría de dos nodos; el clúster sobrevive la caída total de cualquier servidor sin perder datos ni detener el servicio.

Todo el laboratorio corre sobre **CentOS Stream 10**. Lejos del mito repetido de que «CentOS murió», CentOS Stream 10 es la rama pública de entrega continua *upstream* de Red Hat Enterprise Linux 10: conserva estabilidad ABI/API a lo largo de todo el ciclo mayor, aporta **SELinux en modo Enforcing**, **Podman Quadlets** nativos en Systemd y soporte de primera clase en **EPEL 10** y **CRB**, incluyendo el paquete oficial de **Caddy**. Es una plataforma empresarial abierta lista para cargas de trabajo reales.

Como en toda la serie, seguirás nuestra regla pedagógica de oro: **«Manual Primero, Automatización Después»**, respetando la jerarquía **FHS 3.0** bajo ``/srv/garage``, la segmentación del cortafuegos **Firewalld** entre las zonas ``public`` e ``internal`` y la terminación HTTPS automática con **Caddy**, **Let's Encrypt** y ``sslip.io``.

1. Prerrequisitos del Laboratorio
=================================

Trabajarás con **tres servidores con CentOS Stream 10** enlazados en la misma VLAN privada RFC 1918:

* **Nodo 0** ``0.garage.linenes.tld`` en zona ``z1``: nodo de almacenamiento Garage S3 y puerta de enlace HTTPS con Caddy.
* **Nodo 1** ``1.garage.linenes.tld`` en zona ``z2``: nodo par de almacenamiento Garage S3.
* **Nodo 2** ``2.garage.linenes.tld`` en zona ``z3``: nodo par de almacenamiento Garage S3.

A. Tu Saldo de Regalo de $20 USD en Cherry Servers
--------------------------------------------------

Para practicar en infraestructura real sin gastar de tu bolsillo, contamos con el patrocinio directo de **Cherry Servers** para la comunidad:

* **Regístrate aquí:** `Portal de bienvenida de Cherry Servers con $20 USD de crédito <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__
* **Código promocional:** ``LinuxEnEspanol``

Con ese enlace y código recibirás **$20 USD de crédito**. Las tres instancias **Cloud VPS 1** juntas cuestan ~$0.045 EUR/hora, cerca de ~$0.05 USD/hora; tres horas completas de práctica consumen alrededor de **$0.14 USD**. Si destruyes tus servidores al terminar con ``tofu destroy``, te sobrará saldo para completar los 10 módulos de la serie.

B. Tu Estación de Trabajo y Llave SSH Ed25519
---------------------------------------------

Puedes ejecutar el laboratorio desde tu computadora con **Fedora Linux** o desde una estación de control con **CentOS Stream 10**. El acceso como ``root`` en los servidores remotos usa exclusivamente autenticación por **llave SSH Ed25519**, nunca contraseñas.

Verifica o genera tu par de llaves Ed25519 en ``~/.ssh/id_ed25519.pub`` y cárgalo en ``ssh-agent`` para evitar escribir tu frase de paso en cada sesión:

.. code-block:: bash

   # Si aún no tienes tu par de llaves SSH Ed25519, genéralo:
   ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"

   # Inicia ssh-agent en tu sesión actual y carga tu llave privada:
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_ed25519
   ssh-add -l

Instala en tu estación de trabajo el cliente S3 ``rclone``, **OpenTofu** y las utilidades de red y JSON:

* **En Fedora Linux:**

  .. code-block:: bash

     sudo dnf -y install openssh-clients git-core curl jq rclone opentofu

* **En CentOS Stream 10:**

  .. code-block:: bash

     sudo dnf -y install epel-release dnf-plugins-core
     sudo dnf -y install openssh-clients git-core curl jq rclone
     curl --proto '=https' --tlsv1.2 -fsSL -o install-opentofu.sh https://get.opentofu.org/install-opentofu.sh
     sudo bash install-opentofu.sh --install-method rpm
     rm -f install-opentofu.sh

C. Creación de los Tres Nodos para la Práctica Manual
-----------------------------------------------------

Para construir el clúster paso a paso en la Sección 2, aprovisiona tres instancias **Cloud VPS 1** ``B1-1-1gb-20s-shared`` con **CentOS Stream 10** dentro del mismo proyecto y la misma región, por ejemplo ``LT-Siauliai``, asociando tu llave SSH Ed25519:

#. **Opción 1, desde el portal web de Cherry Servers:** Entra a tu proyecto, despliega tres servidores ``Cloud VPS 1`` con imagen ``CentOS Stream 10`` y asigna los nombres de host ``0.garage.linenes.tld``, ``1.garage.linenes.tld`` y ``2.garage.linenes.tld``. Cherry Servers conecta automáticamente los nodos del mismo proyecto a una VLAN privada compartida.
#. **Opción 2, con OpenTofu sin aprovisionamiento automático:** Usa los manifiestos de la Sección 3 fijando ``enable_bootstrap = false`` en ``terraform.tfvars``. Así OpenTofu crea únicamente los tres servidores limpios con tu llave SSH para que configures cada capa a mano.

.. note::
   **Uso de** ``sslip.io`` **y máquinas virtuales locales detrás de NAT:** En servidores en la nube con IP pública, el servicio DNS comodín ``sslip.io`` resuelve automáticamente nombres como ``s3.203.0.113.10.sslip.io`` hacia ``203.0.113.10`` sin comprar un dominio, lo que permite que Caddy tramite certificados reales de **Let's Encrypt**. Si practicas en máquinas virtuales locales sobre KVM/libvirt o VirtualBox sin salida pública alcanzable por Let's Encrypt, agrega la directiva ``tls internal`` dentro de cada bloque del ``Caddyfile`` en el Paso F y confía en la autoridad certificadora local de Caddy o usa ``--no-check-certificate`` en ``rclone`` y ``curl -k`` solo para tus pruebas locales.

2. Construcción y Configuración Manual vía SSH, El Núcleo del Aprendizaje
=========================================================================

Antes de conectarte, obtén las **tres direcciones IPv4 públicas** de tus servidores:

* Si los creaste desde el portal de Cherry Servers, abre tu proyecto, entra a **Servers**, selecciona cada instancia y copia el campo **Primary IP**.
* Si los desplegaste limpios con OpenTofu usando ``enable_bootstrap = false``, consulta ``node0_public_ip``, ``node1_public_ip`` y ``node2_public_ip`` con ``tofu output``.

En tu **estación de trabajo local**, exporta las tres direcciones públicas. Mantén esta pestaña abierta para las verificaciones del Paso G y abre tres pestañas adicionales para conectarte por SSH a cada servidor:

.. code-block:: bash

   # En tu estación de trabajo: sustituye por las IP públicas reales de tus tres nodos
   export IP_PUBLICA_NODO_0="203.0.113.10"
   export IP_PUBLICA_NODO_1="203.0.113.11"
   export IP_PUBLICA_NODO_2="203.0.113.12"

   # Abre cada sesión SSH en una pestaña dedicada de tu terminal
   ssh "root@${IP_PUBLICA_NODO_0}"
   ssh "root@${IP_PUBLICA_NODO_1}"
   ssh "root@${IP_PUBLICA_NODO_2}"

Paso A: Red Privada Dual-NIC, Reloj NTP y Repositorios EPEL 10
--------------------------------------------------------------

Cada servidor **Cloud VPS** en Cherry Servers incluye dos interfaces de red configuradas de fábrica:

* ``eth0``: interfaz pública WAN con tu dirección IPv4 expuesta a internet.
* ``ens4``: interfaz privada conectada a la **VLAN interna RFC 1918** ``10.x.x.0/24`` compartida por tu proyecto. Todo el tráfico interno de Garage entre nodos viajará exclusivamente por esta interfaz.

Antes de instalar paquetes, comprueba dos pilares críticos en cada servidor: que **SELinux** esté activo en modo ``Enforcing`` con ``sestatus`` y que el reloj del sistema esté sincronizado con ``chronyc tracking``. Como aprendiste en el **Cómo 04**, la sincronización de tiempo no es cosmética: el protocolo de firma **S3 SigV4** rechaza peticiones cuando existe un desfase superior a 15 minutos entre cliente y servidor, y los metadatos **CRDT** de Garage dependen de relojes coherentes entre pares.

Ejecuta el siguiente bloque dentro de la sesión SSH de **cada uno de los tres nodos**, ajustando ``NOMBRE_NODO`` a ``0.garage.linenes.tld`` en Nodo 0, ``1.garage.linenes.tld`` en Nodo 1 y ``2.garage.linenes.tld`` en Nodo 2:

.. code-block:: bash

   # En Nodo 0 usa "0.garage.linenes.tld"; en Nodo 1 usa "1.garage.linenes.tld"; en Nodo 2 usa "2.garage.linenes.tld"
   export NOMBRE_NODO="0.garage.linenes.tld"
   hostnamectl set-hostname "${NOMBRE_NODO}"

   sestatus
   chronyc tracking
   ip -4 -o addr show scope global

   # Captura la IPv4 privada RFC 1918 ignorando interfaces virtuales de contenedores
   export IP_PRIVADA_NODO
   IP_PRIVADA_NODO=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
   printf 'Nodo: %s | IP privada VLAN: %s\n' "${NOMBRE_NODO}" "${IP_PRIVADA_NODO}"

Anota las tres direcciones privadas impresas en pantalla, por ejemplo ``10.202.8.5`` para Nodo 0, ``10.202.8.49`` para Nodo 1 y ``10.202.8.12`` para Nodo 2; las necesitarás en los Pasos D y F.

Activa **EPEL 10** y el repositorio **CRB** e instala las herramientas base en **los tres nodos**:

.. code-block:: bash

   # Ejecuta en los tres nodos: Nodo 0, Nodo 1 y Nodo 2
   dnf -y install epel-release
   /usr/bin/crb enable
   dnf -y install podman firewalld jq curl dnf-automatic

Ahora instala **Caddy** y ``policycoreutils-python-utils`` **únicamente en el Nodo 0**. Este último paquete provee ``semanage``, que usarás en el Paso F para etiquetar ``/var/log/caddy``; en los Nodos 1 y 2 no hace falta porque Podman administra las etiquetas SELinux de los contenedores automáticamente:

.. code-block:: bash

   # Ejecuta únicamente en Nodo 0
   dnf -y install caddy policycoreutils-python-utils

Paso B: Segmentación de Firewalld entre ``public`` e ``internal``
-----------------------------------------------------------------

Habilita siempre el cortafuegos **antes** de arrancar contenedores o proxies inversos. Los cuatro puertos de Garage, ``3900`` S3 API, ``3901`` RPC entre nodos, ``3902`` S3 Web y ``3903`` Admin API, nunca deben exponerse a internet: el puerto ``3903`` controla toda la administración del clúster. Asocia los bloques RFC 1918 a la zona ``internal`` y abre esos cuatro puertos únicamente ahí.

Ejecuta primero este bloque en **los tres nodos**:

.. code-block:: bash

   # Ejecuta en los tres nodos: Nodo 0, Nodo 1 y Nodo 2
   systemctl --now enable firewalld

   firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
   firewall-cmd --permanent --zone=internal --add-source=192.168.0.0/16
   firewall-cmd --permanent --zone=internal --add-source=172.16.0.0/12
   firewall-cmd --permanent --zone=internal --add-port=3900/tcp
   firewall-cmd --permanent --zone=internal --add-port=3901/tcp
   firewall-cmd --permanent --zone=internal --add-port=3902/tcp
   firewall-cmd --permanent --zone=internal --add-port=3903/tcp
   firewall-cmd --reload

Abre HTTP y HTTPS en la zona ``public`` **únicamente en el Nodo 0**, que es el único servidor que recibirá tráfico externo hacia Caddy y los retos de Let's Encrypt:

.. code-block:: bash

   # Ejecuta únicamente en Nodo 0
   firewall-cmd --permanent --zone=public --add-service=http
   firewall-cmd --permanent --zone=public --add-service=https
   firewall-cmd --reload

Comprueba la separación de zonas en **los tres nodos**:

.. code-block:: bash

   # Ejecuta en los tres nodos para confirmar el aislamiento
   firewall-cmd --get-active-zones
   firewall-cmd --zone=internal --list-all
   firewall-cmd --zone=public --list-all

En los tres servidores, la zona ``internal`` mostrará las tres subredes RFC 1918 y los puertos ``3900/tcp`` a ``3903/tcp``. En ``public``, únicamente el Nodo 0 tendrá ``http`` y ``https`` además de ``ssh``; los Nodos 1 y 2 mantendrán su cara pública cerrada a todo salvo ``ssh``.

Paso C: Estructura FHS 3.0 y Configuración de Garage ``v2.6.0``
---------------------------------------------------------------

Siguiendo **FHS 3.0**, alojarás los metadatos SQLite y bloques de objetos bajo ``/srv/garage`` y la configuración bajo ``/etc/garage``. Los tres nodos deben compartir exactamente el mismo secreto RPC de 256 bits para autenticar el tráfico entre pares y el mismo token de la API de administración.

Genera e imprime ambos secretos **únicamente en el Nodo 0**:

.. code-block:: bash

   # Ejecuta únicamente en Nodo 0 y copia ambos valores impresos
   export SECRETO_RPC
   export TOKEN_ADMIN
   SECRETO_RPC=$(openssl rand -hex 32)
   TOKEN_ADMIN=$(openssl rand -hex 32)

   printf 'SECRETO_RPC=%s\nTOKEN_ADMIN=%s\n' "${SECRETO_RPC}" "${TOKEN_ADMIN}"

Ahora ve a tus sesiones SSH del **Nodo 1** y del **Nodo 2** y exporta exactamente esos dos valores copiados del Nodo 0 antes de escribir la configuración:

.. code-block:: bash

   # Ejecuta en Nodo 1 y Nodo 2 pegando los valores exactos impresos en Nodo 0
   export SECRETO_RPC="pega_aqui_el_SECRETO_RPC_de_nodo_0"
   export TOKEN_ADMIN="pega_aqui_el_TOKEN_ADMIN_de_nodo_0"

Con ``IP_PRIVADA_NODO``, ``SECRETO_RPC`` y ``TOKEN_ADMIN`` ya definidos en cada terminal, crea la estructura de directorios con permisos ``0750`` y genera ``/etc/garage/garage.toml`` bajo ``umask 027`` en **los tres nodos**:

.. code-block:: bash

   # Ejecuta en los tres nodos: Nodo 0, Nodo 1 y Nodo 2
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
   rpc_public_addr = "${IP_PRIVADA_NODO}:3901"
   rpc_secret = "${SECRETO_RPC}"
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
   admin_token = "${TOKEN_ADMIN}"
   EOF
   umask 022
   chown root:root /etc/garage/garage.toml
   chmod 640 /etc/garage/garage.toml

.. important::
   La imagen ``docker.io/dxflrs/garage:v2.6.0`` se construye desde ``FROM scratch`` como binario estático y no contiene ``/bin/sh``; toda administración del clúster se ejecuta mediante ``podman exec garage /garage ...``. Además, **nunca ejecutes** ``restorecon`` sobre ``/srv/garage`` ni sobre ``/etc/garage/garage.toml`` cuando uses volúmenes con sufijo ``:Z`` o ``:ro,Z``: Podman asigna a esas rutas etiquetas ``container_file_t`` con categorías **MCS** exclusivas del contenedor, y ``restorecon`` las revertiría a ``var_t`` o ``etc_t``, provocando denegaciones inmediatas bajo SELinux Enforcing.

Paso D: Podman Quadlet en Systemd y Malla de 3 Nodos
----------------------------------------------------

En lugar de comandos manuales ``podman run`` difíciles de mantener, declara la unidad nativa **Podman Quadlet** en ``/etc/containers/systemd/garage.container`` en **los tres nodos**. Como el bloque se genera con ``cat << EOF >``, el intérprete sustituirá automáticamente ``NOMBRE_NODO`` e ``IP_PRIVADA_NODO`` definidos en el Paso A, enlazando los puertos únicamente a ``127.0.0.1`` y a la IP privada de cada servidor.

Las unidades Quadlet se generan dinámicamente al ejecutar ``systemctl daemon-reload`` y quedan habilitadas en el arranque gracias a su sección ``[Install]``, por lo que basta arrancar ``garage.service`` con ``systemctl start``:

.. code-block:: bash

   # Ejecuta en los tres nodos usando NOMBRE_NODO e IP_PRIVADA_NODO del Paso A
   cat << EOF > /etc/containers/systemd/garage.container
   [Unit]
   Description=Garage Distributed S3 Storage v2.6.0
   Documentation=https://garagehq.deuxfleurs.fr/
   After=network-online.target firewalld.service
   Wants=network-online.target

   [Container]
   Image=docker.io/dxflrs/garage:v2.6.0
   ContainerName=garage
   HostName=${NOMBRE_NODO}
   PublishPort=127.0.0.1:3900:3900
   PublishPort=${IP_PRIVADA_NODO}:3900:3900
   PublishPort=127.0.0.1:3901:3901
   PublishPort=${IP_PRIVADA_NODO}:3901:3901
   PublishPort=127.0.0.1:3902:3902
   PublishPort=${IP_PRIVADA_NODO}:3902:3902
   PublishPort=127.0.0.1:3903:3903
   PublishPort=${IP_PRIVADA_NODO}:3903:3903
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
   EOF

   chmod 644 /etc/containers/systemd/garage.container
   systemctl daemon-reload
   systemctl start garage.service
   systemctl --now enable podman-auto-update.timer

Comprueba en **los tres nodos** que el servicio Systemd esté activo, que el contenedor aparezca corriendo y que las etiquetas **MCS** de SELinux hayan cambiado a ``container_file_t``:

.. code-block:: bash

   # Verifica en los tres nodos el servicio, el contenedor y las etiquetas MCS
   systemctl --no-pager status garage.service
   podman ps
   ls -Zd /srv/garage/meta /srv/garage/data /etc/garage/garage.toml

Ahora une los tres nodos en una sola malla. Primero obtén en el **Nodo 0** su dirección completa de par en formato ``ID@IP_PRIVADA:3901``:

.. code-block:: bash

   # Ejecuta únicamente en Nodo 0 y copia la línea completa devuelta
   podman exec garage /garage node id

Verás una línea parecida a ``16c4201ec4d318bc...@10.202.8.5:3901``. En las sesiones SSH del **Nodo 1** y del **Nodo 2**, guarda esa cadena exacta en ``DIRECCION_NODO_0`` y conéctate al Nodo 0 por la VLAN privada:

.. code-block:: bash

   # Ejecuta en Nodo 1 y Nodo 2 pegando la salida exacta de garage node id
   DIRECCION_NODO_0="pega_aqui_la_salida_de_garage_node_id"
   podman exec garage /garage node connect "${DIRECCION_NODO_0}"

.. tip::
   **Cómo automatiza el enlace el script de la Sección 3:** En un despliegue desatendido no hay un humano copiando ``garage node id``. Por eso `scripts/bootstrap-peer.bash <scripts/bootstrap-peer.bash>`__ consulta la API de administración v2 del Nodo 0 en ``http://IP_PRIVADA_NODO_0:3903/v2/GetClusterStatus`` autenticándose con ``Authorization: Bearer`` y el secreto ``TOKEN_ADMIN``, extrae el identificador con ``jq`` y ejecuta ``garage node connect`` automáticamente.

Paso E: Topología de 3 Zonas, Bucket S3 y Llaves de Acceso
----------------------------------------------------------

Todas las órdenes de este paso se ejecutan en la sesión SSH del **Nodo 0**. Primero comprueba que los tres nodos aparezcan conectados y saludables en la malla:

.. code-block:: bash

   # En Nodo 0: lista los nodos conectados y sus identificadores hexadecimales
   podman exec garage /garage status

Garage ordena la tabla alfabéticamente por el valor hexadecimal de la columna ``ID``, de modo que las filas pueden aparecer en orden ``0``, ``2`` y ``1`` en lugar de ``0``, ``1`` y ``2``. **Fíjate siempre en la columna** ``Hostname`` antes de copiar cada identificador hacia su variable ``ID_NODO_*``.

Asignarás cada servidor a una zona de disponibilidad independiente ``z1``, ``z2`` y ``z3`` con capacidad declarada ``-c 10G``. En Garage, la capacidad ``-c`` funciona sobre todo como un **peso relativo** para equilibrar las 256 particiones entre los nodos y reservar margen operativo dentro del disco SSD de 20 GB para el sistema operativo, las imágenes de contenedores, los metadatos SQLite y las bitácoras.

Asigna cada ``ID``, inspecciona el borrador con ``layout show`` antes de confirmar y aplica la topología versión 1:

.. code-block:: bash

   # En Nodo 0: pega el ID de cada fila verificando su columna Hostname
   ID_NODO_0="id_hex_de_0.garage.linenes.tld"
   ID_NODO_1="id_hex_de_1.garage.linenes.tld"
   ID_NODO_2="id_hex_de_2.garage.linenes.tld"

   podman exec garage /garage layout assign "${ID_NODO_0}" -z z1 -c 10G -t 0.garage.linenes.tld
   podman exec garage /garage layout assign "${ID_NODO_1}" -z z2 -c 10G -t 1.garage.linenes.tld
   podman exec garage /garage layout assign "${ID_NODO_2}" -z z3 -c 10G -t 2.garage.linenes.tld

   # Revisa el borrador de la topología antes de comprometer los cambios
   podman exec garage /garage layout show

   # Aplica la topología versión 1 y verifica el estado final
   podman exec garage /garage layout apply --version 1
   podman exec garage /garage status

Salida real esperada tras aplicar la topología ``v1`` en Garage, donde puedes observar cómo el orden hexadecimal coloca a ``2.garage.linenes.tld`` antes de ``1.garage.linenes.tld``:

.. code-block:: text

   ==== HEALTHY NODES ====
   ID                Hostname              Address           Tags                    Zone  Capacity  DataAvail         ResyncQueue  Version
   16c4201ec4d318bc  0.garage.linenes.tld  10.202.8.5:3901   [0.garage.linenes.tld]  z1    9.3 GiB   18.0 GiB (90.5%)  0            v2.6.0
   a2de11f79ad106fc  2.garage.linenes.tld  10.202.8.12:3901  [2.garage.linenes.tld]  z3    9.3 GiB   18.1 GiB (90.8%)  0            v2.6.0
   f53947e52d1a681f  1.garage.linenes.tld  10.202.8.49:3901  [1.garage.linenes.tld]  z2    9.3 GiB   18.1 GiB (90.8%)  0            v2.6.0

A continuación crea el bucket ``sitio`` y habilita la publicación web estática sobre el puerto interno ``3902``:

.. code-block:: bash

   # En Nodo 0: crea el bucket y activa el modo de sitio web estático
   podman exec garage /garage bucket create sitio
   podman exec garage /garage bucket website --allow sitio

.. warning::
   **Exposición pública del bucket web:** Al ejecutar ``bucket website --allow sitio``, **cualquier objeto** almacenado dentro de ``sitio`` queda descargable públicamente por HTTPS sin autenticación una vez expuesto a través de Caddy. Nunca guardes respaldos privados, credenciales ni documentos confidenciales en un bucket con modo web habilitado; para datos privados crea siempre un bucket independiente sin ``--allow``.

Ahora crea la llave de acceso ``lab-key``, extrae sus dos credenciales con ``jq`` e imprímelas para copiarlas a tu estación de trabajo en el Paso G. Se conservan los nombres exactos ``AWS_ACCESS_KEY_ID`` y ``AWS_SECRET_ACCESS_KEY`` porque el ecosistema S3 y clientes como ``rclone`` estandarizan esas variables:

.. code-block:: bash

   # En Nodo 0: crea la llave S3, extrae sus credenciales y asigna permisos sobre sitio
   KEY_JSON=$(podman exec garage /garage json-api CreateKey '{"name":"lab-key"}')
   AWS_ACCESS_KEY_ID=$(printf '%s\n' "${KEY_JSON}" | jq -r '.accessKeyId')
   AWS_SECRET_ACCESS_KEY=$(printf '%s\n' "${KEY_JSON}" | jq -r '.secretAccessKey')

   # Copia ambos valores para usarlos en tu estación de trabajo en el Paso G
   printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}"

   podman exec garage /garage bucket allow --read --write --owner sitio --key "${AWS_ACCESS_KEY_ID}"

Paso F: Puerta de Enlace HTTPS con Caddy y SELinux en Modo Enforcing
--------------------------------------------------------------------

Todas las órdenes de este paso se ejecutan **únicamente en el Nodo 0**.

En **CentOS Stream 10** con **EPEL 10**, el paquete oficial de ``caddy`` define reglas SELinux para ``/etc/caddy`` como ``httpd_config_t`` y para ``/var/lib/caddy`` como ``httpd_var_lib_t``, pero no incluye una regla para ``/var/log/caddy``. Si creas bitácoras en esa ruta bajo ``var_log_t``, SELinux en modo **Enforcing** impedirá que el dominio ``httpd_t`` escriba registros. Además, debes validar la configuración siempre como el usuario ``caddy`` mediante ``runuser -u caddy -- caddy validate``: ejecutar ``caddy`` como ``root`` podría crear archivos con propietario ``root:root`` que el servicio no podría abrir después.

Fíjate también en tres directivas clave del ``Caddyfile`` que vas a escribir:

* ``fail_duration 10s`` y ``lb_try_duration 5s``: si uno de los nodos Garage cae, Caddy lo marca como no disponible durante 10 segundos y reintenta automáticamente contra los nodos sanos durante hasta 5 segundos.
* ``header_up Host sitio.web.linenes.tld``: reescribe la cabecera ``Host`` enviada al puerto ``3902`` para que Garage asocie las peticiones de ``web.<IP>.sslip.io`` con el bucket ``sitio`` según ``root_domain = ".web.linenes.tld"``.
* ``setsebool -P httpd_can_network_connect 1``: autoriza de forma persistente a ``httpd_t`` a abrir conexiones salientes por la VLAN privada hacia los puertos ``3900`` y ``3902`` de los tres nodos.

Primero obtén la IP pública del Nodo 0 y define explícitamente las tres IP privadas anotadas en el Paso A, sustituyendo ``10.202.8.49`` y ``10.202.8.12`` por las direcciones reales de tus Nodos 1 y 2:

.. code-block:: bash

   # En Nodo 0: consulta su IP pública y define las tres IP privadas del Paso A
   IP_PUBLICA_NODO_0=$(curl -fs4 --connect-timeout 5 --max-time 10 https://icanhazip.com)
   IP_PRIVADA_NODO_0="${IP_PRIVADA_NODO}"
   IP_PRIVADA_NODO_1="10.202.8.49"
   IP_PRIVADA_NODO_2="10.202.8.12"

   printf 'IP pública Nodo 0: %s | Privadas: %s, %s, %s\n' \
     "${IP_PUBLICA_NODO_0}" "${IP_PRIVADA_NODO_0}" "${IP_PRIVADA_NODO_1}" "${IP_PRIVADA_NODO_2}"

Ahora crea ``/etc/caddy/Caddyfile``, registra el contexto persistente ``httpd_log_t`` sobre ``/var/log/caddy``, habilita el booleano de red, valida bajo el usuario ``caddy``, arranca el servicio y verifica tanto el contexto SELinux como las bitácoras iniciales:

.. code-block:: bash

   mkdir -p /etc/caddy /var/log/caddy
   cat << EOF > /etc/caddy/Caddyfile
   s3.${IP_PUBLICA_NODO_0}.sslip.io {
       reverse_proxy ${IP_PRIVADA_NODO_0}:3900 ${IP_PRIVADA_NODO_1}:3900 ${IP_PRIVADA_NODO_2}:3900 {
           fail_duration 10s
           lb_try_duration 5s
       }

       log {
           output file /var/log/caddy/garage-s3.access.log
           format json
       }
   }

   web.${IP_PUBLICA_NODO_0}.sslip.io {
       reverse_proxy ${IP_PRIVADA_NODO_0}:3902 ${IP_PRIVADA_NODO_1}:3902 ${IP_PRIVADA_NODO_2}:3902 {
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

   ls -Zd /var/log/caddy
   journalctl -u caddy -n 20 --no-pager

En pocos segundos, Caddy resolverá ambos subdominios ``sslip.io``, completará el reto **HTTP-01** o **TLS-ALPN-01** con **Let's Encrypt** y comenzará a balancear las peticiones S3 y web hacia los tres nodos detrás del cortafuegos.

.. note::
   **Puerta de enlace en Nodo 0 frente a producción con alta disponibilidad:** Colocar Caddy únicamente en el Nodo 0 simplifica el laboratorio y mantiene el costo bajo, pero convierte al Nodo 0 en un punto único de entrada HTTPS aunque la capa de almacenamiento Garage sobreviva la caída de cualquier nodo. En un entorno productivo eliminarías ese punto único colocando dos o más proxies inversos detrás de una IP flotante con Keepalived y VRRP, enrutamiento Anycast BGP o un balanceador de carga gestionado.

Paso G: Pruebas Funcionales con ``rclone``, Integridad SHA-256 y Prueba de Caos
-------------------------------------------------------------------------------

Ejecuta todo el Paso G **desde tu estación de trabajo local con Fedora Linux**, fuera de las sesiones SSH.

Primero asegúrate de tener exportadas en tu terminal local las tres direcciones IP públicas del principio de la Sección 2 junto con ``AWS_ACCESS_KEY_ID`` y ``AWS_SECRET_ACCESS_KEY`` impresas en el Paso E, o bien obtenidas desde ``tofu output`` y ``/root/garage-credentials.txt`` si desplegaste con OpenTofu en la Sección 3:

.. code-block:: bash

   # En tu estación de trabajo: sustituye por tus IP públicas y credenciales reales del Paso E
   export IP_PUBLICA_NODO_0="203.0.113.10"
   export IP_PUBLICA_NODO_1="203.0.113.11"
   export IP_PUBLICA_NODO_2="203.0.113.12"
   export AWS_ACCESS_KEY_ID="pega_aqui_tu_AWS_ACCESS_KEY_ID"
   export AWS_SECRET_ACCESS_KEY="pega_aqui_tu_AWS_SECRET_ACCESS_KEY"

Audita **los tres servidores** desde tu estación de trabajo para verificar que los puertos ``3900`` a ``3903`` estén bloqueados desde internet, que **SELinux** permanezca en ``Enforcing`` con cero denegaciones **AVC** recientes y que las ``256`` particiones reporten estado saludable:

.. code-block:: bash

   # 1. Bloqueo WAN de puertos 3900-3903 y auditoría SELinux en los tres nodos
   for ip in "${IP_PUBLICA_NODO_0}" "${IP_PUBLICA_NODO_1}" "${IP_PUBLICA_NODO_2}"; do
     if [[ -z "${ip}" ]]; then
       printf 'Error: falta definir una IP pública de nodo antes de auditar.\n' >&2
       break
     fi
     printf '=== Auditoría de %s ===\n' "${ip}"
     for puerto in 3900 3901 3902 3903; do
       timeout 2 bash -c "exec 3<>/dev/tcp/${ip}/${puerto}" 2>/dev/null \
         && printf '  Puerto %s: abierto\n' "${puerto}" \
         || printf '  Puerto %s: bloqueado\n' "${puerto}"
     done
     ssh -n "root@${ip}" "getenforce && ausearch -m AVC,USER_AVC -ts recent </dev/null || true"
   done

   # 2. Estado de quórum y particiones del clúster
   ssh -n "root@${IP_PUBLICA_NODO_0}" "podman exec garage /garage json-api GetClusterHealth | jq ."

Ahora prueba la API S3 autenticada con **TLS estricto** usando ``rclone``. Las variables ``RCLONE_S3_*`` conservan sus nombres originales en inglés porque ``rclone`` las lee directamente del entorno sin escribir secretos en archivos de configuración en disco:

* ``RCLONE_S3_FORCE_PATH_STYLE=true`` es **obligatorio** con ``sslip.io``: sin esta opción, los clientes S3 anteponen el nombre del bucket como subdominio ``sitio.s3.<IP>.sslip.io``, rompiendo la validación del certificado TLS emitido para ``s3.<IP>.sslip.io``. Con estilo de ruta, las peticiones llegan limpiamente a ``https://s3.<IP>.sslip.io/sitio/...``.
* La sintaxis ``:s3:sitio/...`` declara un conector S3 al vuelo alimentado exclusivamente por las variables ``RCLONE_S3_*``, sin crear ningún archivo ``rclone.conf``.

Sube ``index.html`` y un archivo binario aleatorio de 1 MiB, verifica la suma de verificación SHA-256 al descargarlo y comprueba el uso físico de disco en los tres nodos para confirmar la replicación real en ``z1``, ``z2`` y ``z3``:

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

   rclone copyto :s3:sitio/test-1m.bin descargado-1m.bin
   sha256sum test-1m.bin descargado-1m.bin

   # Confirma la replicación física de bloques y metadatos en los tres servidores
   for ip in "${IP_PUBLICA_NODO_0}" "${IP_PUBLICA_NODO_1}" "${IP_PUBLICA_NODO_2}"; do
     printf '=== Uso en disco en %s ===\n' "${ip}"
     ssh -n "root@${ip}" "du -sh /srv/garage/data /srv/garage/meta"
   done

Comprobarás que las dos sumas SHA-256 de ``test-1m.bin`` y ``descargado-1m.bin`` coinciden bit a bit, y que los tres nodos reflejan alrededor de ``1.1M`` bajo ``/srv/garage/data``, demostrando la replicación física completa en ``z1``, ``z2`` y ``z3``.

Llegó el momento de demostrar la tolerancia real a fallos mediante una **Prueba de Caos** en vivo. Detendrás el servicio ``garage`` en el **Nodo 2**, comprobarás que el clúster pasa a estado ``degraded`` manteniendo quórum en ``2`` de ``3`` nodos, leerás tanto el sitio web como el binario ``test-1m.bin`` verificando su suma SHA-256 y escribirás un objeto nuevo ``quorum-proof.txt`` durante la caída; luego arrancarás el Nodo 2 y observarás la recuperación automática:

.. code-block:: bash

   # 1. Simula la caída total del Nodo 2 y revisa GetClusterHealth
   ssh -n "root@${IP_PUBLICA_NODO_2}" "systemctl stop garage.service"
   ssh -n "root@${IP_PUBLICA_NODO_0}" "podman exec garage /garage json-api GetClusterHealth | jq ."

   # 2. Lectura web, lectura de test-1m.bin con SHA-256 y escritura nueva en quórum 2/3
   curl -fsS --connect-timeout 5 --max-time 10 "https://web.${IP_PUBLICA_NODO_0}.sslip.io/" >/dev/null \
     && printf 'Sitio web operativo con 2/3 nodos\n'
   rclone copyto :s3:sitio/test-1m.bin test-caos.bin
   sha256sum test-1m.bin test-caos.bin
   printf 'escritura-bajo-fallo-nodo2\n' > quorum-proof.txt
   rclone copyto quorum-proof.txt :s3:sitio/quorum-proof.txt

   # 3. Restaura el Nodo 2 y confirma la auto-sanación por resincronización RPC
   ssh -n "root@${IP_PUBLICA_NODO_2}" "systemctl start garage.service"
   sleep 5
   ssh -n "root@${IP_PUBLICA_NODO_0}" "podman exec garage /garage json-api GetClusterHealth | jq ."
   rclone copyto :s3:sitio/quorum-proof.txt quorum-verificado.txt
   sha256sum quorum-proof.txt quorum-verificado.txt

   # 4. Elimina los archivos temporales locales de prueba en tu estación de trabajo
   rm -f index.html test-1m.bin descargado-1m.bin test-caos.bin quorum-proof.txt quorum-verificado.txt

Estado degradado observado en ``GetClusterHealth`` durante la caída controlada del Nodo 2, conservando las ``256`` particiones en quórum:

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

Estado saludable observado en ``GetClusterHealth`` segundos después de reiniciar el Nodo 2 y completar la resincronización:

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

Regresa a tus sesiones SSH en **los tres nodos: Nodo 0, Nodo 1 y Nodo 2**.

En **CentOS Stream 10**, que utiliza **DNF5**, el archivo ``/etc/dnf/automatic.conf`` está empaquetado como ``%ghost`` y no existe en disco tras instalar ``dnf-automatic`` hasta que se copia desde ``/usr/share/dnf5/dnf5-plugins/automatic.conf``. Al mismo tiempo, la directiva ``AutoUpdate=registry`` del Quadlet combinada con la etiqueta fija ``:v2.6.0`` permite que ``podman-auto-update.timer`` aplique reconstrucciones de seguridad publicadas bajo la misma etiqueta ``:v2.6.0`` cuando cambia su *digest* en el registro, evitando saltos inesperados a versiones mayores incompatibles.

Ejecuta en **los tres nodos**:

.. code-block:: bash

   # Ejecuta vía SSH en Nodo 0, Nodo 1 y Nodo 2
   [[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
   sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
   systemctl --now enable dnf-automatic.timer
   systemctl --no-pager status podman-auto-update.timer dnf-automatic.timer

3. Automatización Declarativa con OpenTofu e Infraestructura como Código
========================================================================

Ahora que dominas manualmente la topología de 3 zonas de Garage, la segmentación de Firewalld, las etiquetas ``:Z`` de Podman y el contexto ``httpd_log_t`` de Caddy bajo SELinux Enforcing, consolida toda la arquitectura en infraestructura reproducible con **OpenTofu**.

Instalación de OpenTofu en tu Estación de Trabajo
-------------------------------------------------

Si todavía no instalaste **OpenTofu** en el Paso 1B, hazlo en tu estación de trabajo local y confirma que cuentas con la versión ``>= 1.8.0`` exigida por el módulo:

.. code-block:: bash

   # En Fedora Linux
   sudo dnf -y install opentofu
   tofu version

Si trabajas desde **CentOS Stream 10**, utiliza el instalador oficial RPM mostrado en la Sección 1B antes de verificar ``tofu version``.

Clonar el Repositorio y Explorar Manifiestos
--------------------------------------------

Desde tu estación de trabajo, clona el repositorio oficial y entra al directorio de manifiestos del **Cómo 05**:

.. code-block:: bash

   git clone https://gitlab.com/renich/cherry-servers.git
   cd cherry-servers/05-garage-s3/tofu

Estructura declarativa del módulo ``05-garage-s3``:

* `tofu/provider.tf <tofu/provider.tf>`__: fija OpenTofu ``>= 1.8.0``, el proveedor oficial ``cherryservers/cherryservers ~> 1.5.3`` y ``hashicorp/random ~> 3.6``.
* `tofu/variables.tf <tofu/variables.tf>`__: parametriza la región, el plan ``B1-1-1gb-20s-shared``, la imagen ``centos_stream_10_64bit``, los nombres ``0.garage.linenes.tld`` a ``2.garage.linenes.tld``, la etiqueta fija ``garage_version = "v2.6.0"``, el soporte para reutilizar una llave SSH existente con ``ssh_key_id``, la opción ``spot_instance`` y ``enable_bootstrap``, que puedes poner en ``false`` para crear servidores limpios y practicar manualmente la Sección 2.
* `tofu/main.tf <tofu/main.tf>`__: genera secretos efímeros de 256 bits con ``random_id``, valida la llave SSH con una precondición de ciclo de vida y establece un **grafo acíclico dirigido** de dependencias: como ``garage_node_1`` y ``garage_node_2`` referencian ``local.node0_private_ip`` dentro de ``templatefile()``, OpenTofu aprovisiona primero ``garage_node_0``, obtiene su IP privada en la VLAN interna y después despliega los Nodos 1 y 2 en paralelo inyectándoles esa IP junto con los secretos compartidos.
* `tofu/outputs.tf <tofu/outputs.tf>`__: publica las IP públicas y privadas de los tres nodos, los comandos SSH, los puntos de entrada HTTPS de la API S3 y del sitio web y el comando de consulta de credenciales.

Los Scripts de Arranque Declarativos ``bootstrap-node0.bash`` y ``bootstrap-peer.bash``
---------------------------------------------------------------------------------------

El aprovisionamiento automático se divide en dos scripts idempotentes bajo ``scripts/``:

* `scripts/bootstrap-node0.bash <scripts/bootstrap-node0.bash>`__: configura el nombre de host del Nodo 0, activa EPEL 10 y CRB, instala Podman, Caddy y ``policycoreutils-python-utils``, aplica las reglas de Firewalld antes de levantar contenedores, escribe ``/etc/garage/garage.toml`` y el Quadlet, arranca un Caddy inicial con ``httpd_log_t`` validado mediante ``runuser -u caddy`` y registra la unidad asíncrona ``garage-cluster-init.service`` arrancada con ``systemctl --no-block start``. Esa unidad espera en segundo plano a que los tres nodos se enlacen, aplica la topología ``v1`` en ``z1``, ``z2`` y ``z3``, crea el bucket ``sitio`` y la llave ``lab-key`` en ``/root/garage-credentials.txt`` con permisos ``0600``, y recarga ``/etc/caddy/Caddyfile`` con los tres nodos balanceados.
* `scripts/bootstrap-peer.bash <scripts/bootstrap-peer.bash>`__: ejecuta únicamente en Nodos 1 y 2, instala el conjunto mínimo sin Caddy ni ``policycoreutils-python-utils``, cierra la zona ``public`` a solo SSH mientras abre ``3900`` a ``3903`` únicamente en ``internal``, levanta el Quadlet de Garage, consulta ``http://${NODE0_PRIVATE_IP}:3903/v2/GetClusterStatus`` con el token administrativo hasta obtener el identificador del Nodo 0 y une el nodo a la malla con ``garage node connect``.

.. note::
   En instancias **Cloud VPS con CentOS Stream 10** de Cherry Servers, ``cloud-init status`` transiciona a estado ``disabled`` al concluir la fase inicial. Inspecciona siempre el avance real con ``tail -f /var/log/user-data.log`` en cada nodo y con ``journalctl -u garage-cluster-init -n 50 --no-pager`` en el Nodo 0.

Configurar Variables Locales y Desplegar con ``tofu apply``
-----------------------------------------------------------

Antes de editar ``terraform.tfvars``, reúne tus cuatro valores de entrada directamente desde el portal de Cherry Servers y tu terminal local:

* ``cherry_auth_token``: crea una llave de API personal en `Settings, API Keys de Cherry Servers <https://portal.cherryservers.com/settings/api-keys>`__ mediante **Create API Key** y copia el token generado.
* ``project_id``: abre la sección **Projects** en el portal de Cherry Servers y copia el identificador numérico que aparece junto al nombre de tu proyecto o en su URL.
* ``ssh_public_key``: imprime tu llave pública Ed25519 en tu estación de trabajo con ``cat ~/.ssh/id_ed25519.pub`` y pega la línea completa.
* ``ssh_key_id``: opcional; si esa llave Ed25519 ya está registrada en tu cuenta de Cherry Servers, abre **SSH Keys** en el portal, copia su identificador numérico y descomenta ``ssh_key_id`` para reutilizarla sin recibir errores de llave duplicada.

Copia la plantilla y protege inmediatamente sus permisos a ``0600`` para impedir que otros usuarios locales lean tu token:

.. code-block:: bash

   cp terraform.tfvars.example terraform.tfvars
   chmod 600 terraform.tfvars

Edita ``terraform.tfvars`` con tus datos tomando este ejemplo completo como referencia:

.. code-block:: hcl

   cherry_auth_token = "TU_API_TOKEN_AQUI"
   project_id        = 123456
   ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tu_correo@ejemplo.com"
   # ssh_key_id      = "TU_SSH_KEY_ID" # Descomenta si tu llave SSH ya está registrada en Cherry Servers
   region            = "LT-Siauliai"
   server_plan       = "B1-1-1gb-20s-shared"
   server_image      = "centos_stream_10_64bit"
   garage_version    = "v2.6.0"
   spot_instance     = false
   enable_bootstrap  = true

.. warning::
   **Disciplina de costos antes de aplicar:** Confirmar ``tofu apply`` crea inmediatamente **tres servidores facturables** en Cherry Servers a ~$0.045 EUR/hora, unos ~$0.05 USD/hora en conjunto, descontados de tu crédito de $20 USD hasta que los elimines en la Sección 4. Revisa siempre la salida de ``tofu plan`` antes de confirmar con ``yes``.

Inicializa los proveedores, valida los manifiestos, revisa el plan y despliega el clúster completo:

.. code-block:: bash

   tofu init
   tofu validate
   tofu plan
   tofu apply

Tras confirmar con ``yes``, OpenTofu mostrará un bloque de salidas similar a este:

.. code-block:: text

   Outputs:

   credentials_command = "ssh root@203.0.113.10 cat /root/garage-credentials.txt"
   node0_private_ip = "10.202.8.5"
   node0_public_ip = "203.0.113.10"
   node1_private_ip = "10.202.8.49"
   node1_public_ip = "203.0.113.11"
   node2_private_ip = "10.202.8.12"
   node2_public_ip = "203.0.113.12"
   s3_endpoint_url = "https://s3.203.0.113.10.sslip.io"
   ssh_node0_command = "ssh root@203.0.113.10"
   ssh_node1_command = "ssh root@203.0.113.11"
   ssh_node2_command = "ssh root@203.0.113.12"
   web_endpoint_url = "https://web.203.0.113.10.sslip.io"

Espera entre 2 y 3 minutos para que los tres nodos descarguen la imagen de Garage, formen la malla por la VLAN privada y concluyan ``garage-cluster-init.service``. Luego verifica la finalización del aprovisionamiento y consulta tus credenciales S3 generadas en ``/root/garage-credentials.txt``:

.. code-block:: bash

   # Confirma que garage-cluster-init.service llegó a estado active en el Nodo 0
   ssh -n "root@$(tofu output -raw node0_public_ip)" "systemctl is-active garage-cluster-init.service"
   ssh -n "root@$(tofu output -raw node0_public_ip)" "journalctl -u garage-cluster-init -n 30 --no-pager"

   # Muestra las salidas y lee el archivo de credenciales S3 generado
   tofu output
   ssh -n "root@$(tofu output -raw node0_public_ip)" "cat /root/garage-credentials.txt"

Cuando ``systemctl is-active`` devuelva ``active`` y leas tus llaves en ``/root/garage-credentials.txt``, podrás ejecutar exactamente las mismas pruebas de ``rclone``, replicación y caos del Paso G sobre tu clúster automatizado.

4. Destrucción de los Servidores y Control de Costos
====================================================

Al terminar tus pruebas con S3 y tus experimentos de quórum, destruye la infraestructura para conservar tu saldo patrocinado de $20 USD para los próximos módulos.

Captura primero las tres IP públicas **antes** de ejecutar ``tofu destroy`` para limpiar luego tus entradas en ``~/.ssh/known_hosts``, destruye los recursos y confirma que el estado quede vacío:

.. code-block:: bash

   # Desde cherry-servers/05-garage-s3/tofu en tu estación de trabajo
   IP_PUBLICA_NODO_0=$(tofu output -raw node0_public_ip)
   IP_PUBLICA_NODO_1=$(tofu output -raw node1_public_ip)
   IP_PUBLICA_NODO_2=$(tofu output -raw node2_public_ip)

   tofu destroy

   ssh-keygen -R "${IP_PUBLICA_NODO_0}"
   ssh-keygen -R "${IP_PUBLICA_NODO_1}"
   ssh-keygen -R "${IP_PUBLICA_NODO_2}"
   tofu state list

Ten presente cómo actúa ``tofu destroy`` sobre tu llave SSH: si reutilizaste una llave existente mediante ``ssh_key_id``, OpenTofu no la administra y la conserva intacta en tu cuenta de Cherry Servers; si dejaste ``ssh_key_id`` comentado y OpenTofu registró ``garage-deployer-key`` a partir de ``ssh_public_key``, la destruirá limpiamente junto con los tres servidores.

Cuando hayas concluido definitivamente tus pruebas y los retos de la Sección 5, borra tu archivo local ``terraform.tfvars`` para no dejar el token de API en disco; si piensas redesplegar para resolver los retos, consérvalo hasta terminar:

.. code-block:: bash

   # Ejecuta al concluir definitivamente el laboratorio y la Sección 5
   rm -f terraform.tfvars

Por último, si durante la Sección 2 creaste servidores manualmente desde el portal web de Cherry Servers, entra a **Projects**, abre **Servers** y elimínalos manualmente con **Terminate**, verificando además que no hayan quedado archivos temporales de prueba como ``test-1m.bin`` en tu estación de trabajo.

5. Retos de Aprendizaje y Práctica
==================================

Pon a prueba tu criterio operativo completando estos tres ejercicios sin soluciones prefabricadas:

#. **Reto 1: Dominio propio y múltiples buckets web detrás de Caddy**

   * **Objetivo:** Reemplaza los puntos de entrada HTTPS temporales de ``sslip.io`` por registros ``A`` y ``CNAME`` bajo un dominio DNS real que controles, configurando un segundo bucket público servido desde ``static.tudominio.tld`` mediante otro bloque en ``/etc/caddy/Caddyfile``.
   * **Criterio de éxito:** Ambos sitios responden con certificado TLS válido de Let's Encrypt, ``caddy validate`` pasa bajo el usuario ``caddy`` y ``ausearch -m AVC,USER_AVC -ts recent`` muestra cero denegaciones.

#. **Reto 2: Expansión dinámica del clúster con un cuarto nodo y migración segura**

   * **Objetivo:** Despliega una cuarta instancia CentOS Stream 10 dentro de la misma VLAN privada, conéctala a la malla y agrégala a la topología en una zona ``z4`` aplicando la transición a la versión siguiente en Garage sin interrumpir lecturas sobre ``sitio``.
   * **Criterio de éxito:** ``podman exec garage /garage status`` lista los cuatro nodos activos con sus zonas asignadas, ``ResyncQueue`` llega a ``0`` en todos y la suma de verificación ``sha256sum`` de ``test-1m.bin`` permanece intacta.

#. **Reto 3: Portabilidad a Debian 13 o Ubuntu Server 26.04 LTS**

   * **Objetivo:** Reproduce manualmente la topología de 3 nodos y el proxy inverso TLS sobre **Debian 13** o **Ubuntu Server 26.04 LTS**, adaptando el gestor de paquetes ``apt``, el cortafuegos ``nftables`` o ``ufw`` y los perfiles **AppArmor** en reemplazo de **SELinux Enforcing**.
   * **Criterio de éxito:** El clúster alcanza quórum sano de 256 particiones, los puertos internos ``3900`` a ``3903`` quedan bloqueados desde internet y ``rclone`` transfiere archivos con validación TLS estricta.

Referencias Oficiales
=====================

* `CentOS Stream, documentación oficial <https://www.centos.org/centos-stream/>`__
* `Extra Packages for Enterprise Linux, EPEL <https://docs.fedoraproject.org/en-US/epel/>`__
* `Garage, guía de inicio rápido <https://garagehq.deuxfleurs.fr/documentation/quick-start/>`__
* `Garage, manual de referencia de configuración <https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/>`__
* `Garage, exposición de sitios web estáticos <https://garagehq.deuxfleurs.fr/documentation/cookbook/exposing-websites/>`__
* `rclone, documentación del conector S3 <https://rclone.org/s3/>`__
* `Podman Quadlets, página de manual podman-systemd.unit <https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html>`__
* `Caddy, documentación oficial de Caddyfile <https://caddyserver.com/docs/caddyfile>`__
* `Red Hat Enterprise Linux 10, uso de SELinux <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/secure-getting_started_with_selinux>`__
* `OpenTofu, documentación oficial <https://opentofu.org/docs/>`__

Dudas y Preguntas
=================

¿Encontraste algún detalle técnico, quieres proponer una mejora o compartir tus resultados del quórum distribuido? Abre un reporte o incidencia en el repositorio oficial o súmate a la conversación en la comunidad:

* `Abrir un reporte o incidencia en GitLab <https://gitlab.com/renich/cherry-servers/-/issues>`__
* `Comunidad r/LinuxEnEspanol en Reddit <https://www.reddit.com/r/LinuxEnEspanol/>`__

Cuando termines tus retos, te espera el siguiente paso de la serie: **Cómo 06: Clúster K3s Mononodo** sobre CentOS Stream 10.

Licencia
========

Esta guía está publicada bajo la **Licencia de Documentación Libre GNU v1.3 o posterior**, `GFDL-1.3-or-later <../LICENSE>`__. Los scripts de automatización y manifiestos de OpenTofu incluidos en este módulo se licencian bajo **GPL-3.0-or-later**.
