===================================================================================
Cómo desplegar tu propio servidor de Luanti en CentOS Stream 10 con OpenTofu y COPR
===================================================================================

:Módulo: Cómo 01: Servidor Dedicado de Luanti, Sandbox Voxel FOSS
:Versión: ``v1.0.0``
:Fecha: ``2026-08-18``
:Directorio: `01-luanti-tofu <https://gitlab.com/renich/cherry-servers/-/tree/master/01-luanti-tofu>`__
:Licencia: `GFDL-1.3-or-later <../LICENSE>`__
:Tipo de instancia: Cloud VPS 2, ``B2-2-2gb-40s-shared``, Gen 2 con 2 vCPU, 2 GB RAM y 40 GB SSD
:Costo por hora: ~$0.033 EUR/hora, ~$0.035 USD/hora
:Tiempo promedio: 1 hora
:Gasto estimado total: ~$0.03 USD

¡Hola! 👋

Te doy una calurosa bienvenida a esta **serie práctica de «Cómos» de infraestructura y administración de sistemas en Linux**, creada para toda la **comunidad de software libre de Latinoamérica** y para ti, que disfrutas entender cómo funcionan los sistemas desde sus cimientos.

A lo largo de esta secuencia de 10 Cómos prácticos y autosuficientes, explorarás desde servidores de juegos y proxies inversos con contenedores, hasta almacenamiento distribuido S3, clústeres de Kubernetes con K3s e inferencia local de modelos de Inteligencia Artificial. En este **primer Cómo**, pondrás en marcha tu propio servidor dedicado de **Luanti**, el motor sandbox de bloques 100% libre antes conocido como *Minetest*.

Si has escuchado el rumor de que "CentOS murió", en este laboratorio comprobarás lo contrario con hechos: a diferencia de las antiguas reconstrucciones cerradas posteriores a cada lanzamiento, **CentOS Stream 10** es la rama abierta de entrega continua aguas arriba de **Red Hat Enterprise Linux 10**. Mantiene estabilidad de ABI y API durante todo su ciclo mayor, contribución abierta, **SELinux en modo Enforcing** por defecto y soporte directo para **EPEL 10** y **CRB**, lo que ofrece una base empresarial confiable para cualquier carga de trabajo.

Siguiendo la filosofía pedagógica de esta serie, **«Manual Primero, Automatización Después»**, primero construirás y configurarás el servicio paso a paso directamente en tu terminal para dominar su arquitectura, y después empaquetarás todo en una receta reproducible con **OpenTofu**.

1. Prerrequisitos del Laboratorio
=================================

Para completar este Cómo necesitas:

#. Un servidor con **CentOS Stream 10** en la nube, o una máquina virtual local de pruebas, con acceso SSH como ``root`` exclusivamente mediante clave pública Ed25519 en ``~/.ssh/id_ed25519.pub``.

   * **Saldo promocional de $20 USD:** Puedes desplegar tu servidor en la nube sin costo gracias al patrocinio de **Cherry Servers** para la comunidad. Regístrate en el `Portal de Cherry Servers <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__ utilizando el código promocional ``LinuxEnEspanol`` para recibir **$20 USD de crédito**.
   * Si aún no tienes un par de llaves Ed25519, genéralo en tu estación de trabajo y cárgalo en ``ssh-agent`` para autenticarte sin repetir la frase de paso en cada sesión:

   .. code-block:: bash

      ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"
      eval "$(ssh-agent -s)"
      ssh-add ~/.ssh/id_ed25519

   * **Alternativa rápida para aprovisionar la instancia limpia:** Si prefieres no crear el servidor desde el panel web, puedes usar OpenTofu de la Sección 3 con ``enable_bootstrap = false`` en ``terraform.tfvars`` para levantar una instancia CentOS Stream 10 vacía y practicar toda la Sección 2 de forma manual.

#. Clientes y herramientas locales en tu estación de trabajo con **Fedora Linux**. En tu equipo de escritorio trabajas como usuario regular y empleas ``sudo`` solo al instalar paquetes del sistema; en cambio, en el servidor remoto operarás directamente como ``root`` mediante tu llave Ed25519, sin anteponer ``sudo`` a ningún comando:

   .. code-block:: bash

      sudo dnf -y install openssh-clients git-core minetest

   .. note::
      **Sobre el nombre del paquete:** Aunque el proyecto cambió de nombre oficialmente a **Luanti** a partir de la versión 5.10+, en los repositorios oficiales de Fedora el paquete RPM de escritorio conserva el nombre histórico ``minetest``. Al instalar ``minetest``, tu sistema instala el lanzador de escritorio con la interfaz moderna de Luanti.

2. Construcción y Configuración Manual vía SSH, El Núcleo del Aprendizaje
=========================================================================

Antes de conectarte, prepara tu instancia de **CentOS Stream 10**:

* **En Cherry Servers:** Abre el portal, entra a **SSH Keys** y registra el contenido de ``~/.ssh/id_ed25519.pub``. Después crea una instancia nueva eligiendo el plan ``B2-2-2gb-40s-shared``, **Cloud VPS 2**, imagen **CentOS Stream 10 64bit**, región ``LT-Siauliai`` y tu llave Ed25519. Cuando el nodo esté activo, entra a su ficha y copia el valor de **Primary IP**. También puedes aprovisionar esta instancia limpia con OpenTofu usando ``enable_bootstrap = false``.
* **En una máquina virtual local:** Si prefieres practicar en KVM/libvirt, obtén la dirección IPv4 de tu VM ejecutando ``ip -4 -o addr show scope global`` dentro de su consola.

En tu estación de trabajo con Fedora, exporta la variable ``IP_DEL_SERVIDOR`` reemplazando la dirección de ejemplo ``203.0.113.10`` por la IP real de tu servidor y abre la sesión SSH:

.. code-block:: bash

   # Reemplaza 203.0.113.10 por la Primary IP real de tu servidor
   export IP_DEL_SERVIDOR="203.0.113.10"
   ssh "root@${IP_DEL_SERVIDOR}"

Paso A: Nombre de Host y Fundamentos de Fedora COPR
---------------------------------------------------

Asigna un nombre de host estructurado al servidor para identificar el nodo con claridad en tus registros y en la terminal:

.. code-block:: bash

   hostnamectl set-hostname 0.luanti.linenes.tld

**COPR**, siglas de *Cool Other Package Repository*, es el sistema oficial de construcción y distribución de paquetes comunitarios del Proyecto Fedora. Permite a mantenedores empaquetar software siguiendo las directrices oficiales de RPM con ``rpmbuild`` y ``mock``, y distribuirlo automáticamente para Fedora, EPEL y CentOS/RHEL.

.. note::
   **Crédito al mantenedor:** Para CentOS Stream 10 y EPEL 10, este Cómo utiliza el repositorio COPR empaquetado y mantenido por **David Herrera**, identificador ``dherrera``, disponible en `copr.fedorainfracloud.org/coprs/dherrera/minetest <https://copr.fedorainfracloud.org/coprs/dherrera/minetest/>`__. En Fedora Linux, el paquete ``minetest-server`` ya forma parte de los repositorios oficiales sin necesidad de habilitar COPR.

Paso B: Habilitar Repositorios e Instalar el Paquete RPM
--------------------------------------------------------

Habilita **EPEL 10**, **CRB** y el repositorio COPR ``dherrera/minetest``, e instala el servidor dedicado junto con ``firewalld``:

.. code-block:: bash

   # 1. Habilitar EPEL 10 y los complementos de DNF
   dnf -y install epel-release dnf-plugins-core
   /usr/bin/crb enable

   # 2. Habilitar el repositorio COPR de Luanti para EPEL 10
   dnf -y copr enable dherrera/minetest

   # 3. Instalar el servidor dedicado y el cortafuegos
   dnf -y install minetest-server firewalld

Cada paso cumple una función concreta dentro del ecosistema de CentOS Stream 10:

* ``epel-release``: activa **EPEL 10**, paquetes comunitarios adicionales mantenidos por Fedora para RHEL 10 y CentOS Stream 10.
* ``/usr/bin/crb enable``: habilita **CRB**, *CodeReady Linux Builder*, indispensable para resolver bibliotecas y dependencias compartidas que requieren los paquetes de EPEL 10 y COPR.
* ``dnf-plugins-core``: proporciona el subcomando ``dnf copr`` para suscribir repositorios COPR con verificación de llaves GPG.
* ``minetest-server`` y ``firewalld``: instalan el binario ``/usr/bin/minetestserver``, el juego base oficial ``minetest_game``, la unidad plantilla ``minetest@.service``, el usuario de sistema sin consola interactiva ``minetest`` y el servicio de cortafuegos dinámico ``firewalld``.

Paso C: Estructura de Datos y Permisos bajo FHS 3.0
---------------------------------------------------

Bajo el estándar **FHS 3.0**, el sistema separa los datos mutables de la aplicación en ``/var/lib/minetest`` de los archivos de configuración estáticos del equipo en ``/etc/minetest``, lo que simplifica copias de seguridad y auditorías. Crea los directorios necesarios y asigna permisos restrictivos ``750`` para que solo el usuario y el grupo ``minetest`` puedan recorrerlos y escribir en ellos, bloqueando la lectura al resto de cuentas locales:

.. code-block:: bash

   # Crear estructura de datos para la instancia por defecto
   mkdir -p /var/lib/minetest/{default,.minetest/games}

   # Asignar propiedad al usuario dedicado del sistema y endurecer permisos
   chown -R minetest:minetest /var/lib/minetest /etc/minetest
   chmod 750 /var/lib/minetest /etc/minetest

Paso D: Configuración del Servidor en ``/etc/minetest/default.conf``
--------------------------------------------------------------------

Crea el archivo de configuración del servidor en ``/etc/minetest/default.conf`` y personaliza ``name`` con el nombre de usuario que usarás como administrador del mundo:

.. code-block:: bash

   cat << 'EOF' > /etc/minetest/default.conf
   # Cuenta administradora del servidor; reemplázala por tu propio nombre de jugador
   name = tu_usuario_admin
   server_name = 0.luanti.linenes.tld
   server_description = Servidor 100% FOSS en CentOS Stream 10 desplegado con OpenTofu y COPR
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

Conviene entender qué controla cada directiva principal antes de encender el servidor:

* ``name``: define el **nombre de usuario de la cuenta administradora** en Luanti. El primer jugador que se registre con ese nombre exacto recibirá todos los privilegios del servidor; reemplaza ``tu_usuario_admin`` por tu usuario personal y nunca dejes un valor genérico de ejemplo en un servidor accesible desde internet.
* ``bind_address`` y ``server_address``: dejar ``bind_address`` sin definir hace que Luanti enlace todas las interfaces de red en ``[::]:30000`` con doble pila IPv4/IPv6. Tampoco se configura ``server_address``, ya que esa directiva solo indica un nombre de dominio público para anunciarse en la lista de servidores cuando ``server_announce = true``, por lo que escribir ``0.0.0.0`` ahí es incorrecto.
* ``port``: puerto UDP de referencia del servidor; en el Paso F verás cómo la unidad Systemd también lee el puerto desde ``/etc/sysconfig/minetest/default.conf``.
* ``default_game``, ``enable_damage``, ``creative_mode``, ``max_users`` y ``server_announce``: seleccionan ``minetest_game`` como juego inicial, habilitan supervivencia con daño, limitan a 25 jugadores concurrentes y mantienen el servidor privado sin publicarlo en el directorio global.
* ``chmod 640``: otorga lectura y escritura al propietario ``minetest``, solo lectura al grupo ``minetest`` y cero acceso a otros usuarios locales.

Paso E: SELinux en Modo Enforcing y Reglas del Cortafuegos
----------------------------------------------------------

CentOS Stream 10 opera con **SELinux en modo Enforcing**. Aplica las etiquetas de seguridad y configura ``firewalld`` **antes** de iniciar el daemon de Luanti, de modo que el servicio nazca ya etiquetado y bajo un cortafuegos activo.

Cuando creas carpetas o archivos manualmente como ``root``, sus contextos SELinux pueden quedar desalineados respecto a la política del sistema; ``restorecon`` restablece las etiquetas correctas en disco. Por su parte, Luanti usa **UDP** en lugar de TCP porque el tráfico voxel envía continuamente posición, física y cambios de bloques en tiempo real, donde la sobrecarga por retransmisiones estrictamente ordenadas de TCP introduciría tirones; Luanti implementa su propia capa fiable sobre UDP:

.. code-block:: bash

   # Confirmar que SELinux opera en modo Enforcing
   getenforce

   # Restaurar contextos de SELinux y verificar las etiquetas aplicadas
   restorecon -Rv /var/lib/minetest /etc/minetest /usr/bin/minetestserver
   ls -lZ /var/lib/minetest /etc/minetest

   # Habilitar el cortafuegos y abrir el puerto UDP 30000 antes de iniciar Luanti
   systemctl --now enable firewalld
   firewall-cmd --permanent --add-port=30000/udp
   firewall-cmd --reload
   firewall-cmd --list-ports

Paso F: Gestión del Servicio en Systemd con ``minetest@.service``
-----------------------------------------------------------------

El paquete RPM incluye una **unidad de servicio Systemd con plantilla** llamada ``minetest@.service``. Esto permite ejecutar múltiples instancias independientes cambiando únicamente el nombre tras la arroba, como ``minetest@default.service`` o ``minetest@pvp.service``.

Antes de arrancar el servicio, inspecciona la definición de la unidad y su archivo de variables de entorno en ``/etc/sysconfig/minetest/default.conf``:

.. code-block:: bash

   # Inspeccionar la unidad plantilla y su archivo de entorno
   systemctl cat minetest@.service
   cat /etc/sysconfig/minetest/default.conf

   # Iniciar y habilitar la instancia por defecto
   systemctl daemon-reload
   systemctl --now enable minetest@default.service

Al revisar ``systemctl cat minetest@.service``, notarás que la unidad exige ``EnvironmentFile=/etc/sysconfig/minetest/%i.conf`` y pasa ``--port $PORT`` directamente al binario ``/usr/bin/minetestserver``. Como los argumentos de línea de comandos prevalecen sobre ``port`` en ``/etc/minetest/default.conf``, si cambias de puerto debes actualizar ``PORT`` en ``/etc/sysconfig/minetest/default.conf``; recuerda este detalle cuando diseñes una segunda instancia en el Reto 2.

Comprueba ahora que el servicio corre sano, que el socket UDP escucha en ``30000``, que la bitácora no reporta errores y que SELinux no registró denegaciones:

.. code-block:: bash

   systemctl --no-pager status minetest@default.service
   ss -ulnp | grep 30000
   journalctl -u minetest@default.service -n 20 --no-pager
   ausearch -m AVC,USER_AVC -ts recent </dev/null || true

En ``systemctl --no-pager status minetest@default.service`` verás una salida activa similar a:

.. code-block:: text

   ● minetest@default.service - Minetest multiplayer server w/ default.conf server config
        Loaded: loaded (/usr/lib/systemd/system/minetest@.service; enabled)
        Active: active (running)
      Main PID: 9647 (minetestserver)
        CGroup: /system.slice/system-minetest.slice/minetest@default.service
                └─9647 /usr/bin/minetestserver --config /etc/minetest/default.conf --port 30000 ...

   ACTION[Main]: Server for gameid="minetest" listening on [::]:30000.

Paso G: Conexión desde el Cliente de Juego
------------------------------------------

#. Abre tu cliente de **Luanti** en tu estación de trabajo y selecciona la pestaña **Unirse a partida**, *Join Game*.
#. En el campo **Dirección**, *Address*, escribe la IP pública de tu servidor y en **Puerto**, *Port*, escribe ``30000``.
#. En el campo **Nombre**, *Name*, escribe el nombre de usuario administrador que personalizaste en la directiva ``name`` de ``/etc/minetest/default.conf``.
#. Haz clic en el botón **Registrar**, *Register*.
#. El cliente abrirá una ventana emergente para **definir y confirmar tu contraseña** en este servidor.
#. Al confirmar, el cliente descargará las texturas y recursos del servidor y entrarás directamente a tu propio mundo voxel con privilegios de administración.

.. note::
   **Para sesiones futuras:** En tus siguientes partidas ya no necesitas pulsar **Registrar**. Escribe tu usuario y contraseña en el formulario principal y haz clic en **Iniciar sesión**, *Login*.

Paso H: Mantenimiento Continuo y Actualizaciones Automáticas
------------------------------------------------------------

Mantener un servidor expuesto en internet al día con parches de seguridad evita deuda técnica desde el primer día. En CentOS Stream 10, ``dnf-automatic`` utiliza DNF5 y marca ``/etc/dnf/automatic.conf`` como archivo fantasma ``%ghost`` en el paquete RPM, guardando la plantilla original en ``/usr/share/dnf5/dnf5-plugins/automatic.conf``; por eso conviene confirmar su existencia antes de modificarla:

.. code-block:: bash

   # Instalar dnf-automatic y crear /etc/dnf/automatic.conf desde la plantilla de DNF5 si falta
   dnf -y install dnf-automatic
   [[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf

   # Habilitar la aplicación automática de actualizaciones y activar el temporizador
   sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
   systemctl --now enable dnf-automatic.timer
   systemctl --no-pager list-timers dnf-automatic.timer

Si decides conservar este mundo a largo plazo, respalda periódicamente ``/var/lib/minetest/default`` y ``/etc/minetest/default.conf`` fuera del servidor.

3. Automatización Declarativa con OpenTofu e Infraestructura como Código
========================================================================

Ahora que conoces cada componente interno, sus contextos SELinux y el funcionamiento del paquete RPM, consolidarás todo el aprovisionamiento del servidor y la puesta en marcha del servicio en una receta reproducible con **OpenTofu** y **Cherry Servers**.

Instalación de OpenTofu en tu Estación de Trabajo
-------------------------------------------------

OpenTofu está disponible como paquete RPM nativo con versión mínima requerida ``1.8.0``.

En **Fedora Linux**, desde los repositorios oficiales:

.. code-block:: bash

   sudo dnf -y install opentofu
   tofu version

En **CentOS Stream 10** y **RHEL 10**, habilitando primero EPEL 10:

.. code-block:: bash

   sudo dnf -y install epel-release
   sudo dnf -y install opentofu
   tofu version

Clonar el Repositorio y Explorar Manifiestos
--------------------------------------------

Clona el repositorio oficial de la serie e ingresa al directorio de OpenTofu del Cómo 01:

.. code-block:: bash

   git clone https://gitlab.com/renich/cherry-servers.git
   cd cherry-servers/01-luanti-tofu/tofu

El laboratorio emplea una arquitectura **plana y lineal**, sin módulos anidados opacos:

* `tofu/provider.tf <tofu/provider.tf>`__: declara OpenTofu ``>= 1.8.0`` y el proveedor oficial de Cherry Servers ``cherryservers/cherryservers``.
* `tofu/variables.tf <tofu/variables.tf>`__: define parámetros como ``region``, ``server_plan``, ``server_image``, ``ssh_key_id``, ``spot_instance``, ``server_port`` y ``enable_bootstrap`` con valores por defecto listos para laboratorio.
* `tofu/main.tf <tofu/main.tf>`__: registra o reutiliza tu llave SSH y aprovisiona la instancia Cloud VPS inyectando el script de arranque.
* `tofu/outputs.tf <tofu/outputs.tf>`__: expone la IP pública, la cadena de conexión para el cliente y el comando SSH.
* `tofu/terraform.tfvars.example <tofu/terraform.tfvars.example>`__: plantilla local para tus credenciales y ajustes personales.

La variable ``enable_bootstrap`` vale ``true`` por defecto para que ``cloud-init`` ejecute automáticamente el script de arranque y deje Luanti listo al primer inicio. Si la cambias a ``false``, OpenTofu crea únicamente el servidor limpio de CentOS Stream 10 para repetir la Sección 2 manualmente.

.. note::
   **Convención del nombre de host:** ``0.luanti.linenes.tld``

   En ingeniería de confiabilidad de sitios, SRE, **no se usan nombres de mascotas** como *"zeus"* o *"servidor1"*. Se aplica un esquema jerárquico FQDN, siglas de *Fully Qualified Domain Name*:

   * ``0``: índice de nodo dentro de una flota en base cero: ``0``, ``1``, ``2``.
   * ``luanti``: servicio o carga de trabajo principal.
   * ``linenes``: identificador del entorno o comunidad, *Linux en Español*.
   * ``tld``: *Top-Level Domain* o Dominio de Nivel Superior, como ``.internal`` o tu dominio propio. Aquí ``.tld`` actúa solo como marcador de posición didáctico; para nombres de prueba reales sin colisiones, los RFC 2606 y RFC 6761 reservan ``.example``, ``.test``, ``.invalid`` y ``.localhost``, mientras que ICANN reservó ``.internal`` para redes privadas.

El Script de Arranque Declarativo ``scripts/bootstrap.bash``
------------------------------------------------------------

OpenTofu renderiza e inyecta automáticamente `scripts/bootstrap.bash <scripts/bootstrap.bash>`__ dentro de ``user_data`` en Cherry Servers:

.. code-block:: hcl

   resource "cherryservers_server" "luanti_node" {
     project_id    = var.project_id
     region        = var.region
     plan          = var.server_plan
     image         = var.server_image
     hostname      = var.server_name
     spot_instance = var.spot_instance
     ssh_key_ids   = [local.active_ssh_key_id]

     # Inyecta el script de arranque codificado en Base64 si enable_bootstrap es true
     user_data = var.enable_bootstrap ? base64encode(templatefile("${path.module}/../scripts/bootstrap.bash", {
       SERVER_NAME = var.server_name
       SERVER_PORT = var.server_port
     })) : null

     tags = {
       Environment = "Lab"
       ManagedBy   = "OpenTofu"
       Series      = "Comos-Linux-FOSS"
       Game        = "Luanti"
     }
   }

El script automatiza exactamente los pasos manuales de la Sección 2: define el nombre de host, habilita EPEL 10, CRB y COPR, instala ``minetest-server``, ``firewalld`` y ``dnf-automatic``, escribe ``/etc/minetest/default.conf``, actualiza ``PORT`` dentro de ``/etc/sysconfig/minetest/default.conf`` para respetar cualquier valor de ``server_port``, aplica ``restorecon`` y el cortafuegos antes de arrancar ``minetest@default.service``, y habilita ``dnf-automatic.timer``. Recuerda personalizar ``name = tu_usuario_admin`` en ``scripts/bootstrap.bash`` o vía SSH en ``/etc/minetest/default.conf`` antes de compartir tu servidor con otras personas.

Configurar Variables Locales y Desplegar con ``tofu apply``
-----------------------------------------------------------

.. warning::
   **Disciplina de costos:** Si realizaste la construcción manual previa en un servidor de Cherry Servers o en una VM local, recuerda apagarlo o destruirlo antes de lanzar este despliegue automatizado para evitar costos simultáneos innecesarios.

Copia la plantilla de ejemplo y restringe sus permisos de inmediato para que ningún otro usuario local pueda leer tu token de API:

.. code-block:: bash

   cp terraform.tfvars.example terraform.tfvars
   chmod 600 terraform.tfvars

Obtén cada valor desde las fuentes oficiales antes de editar ``terraform.tfvars``; recuerda que puedes activar tu cuenta con el `saldo promocional de $20 USD <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__ y el código ``LinuxEnEspanol``:

* ``cherry_auth_token``: ingresa al Portal de Cherry Servers en `portal.cherryservers.com/settings/api-keys <https://portal.cherryservers.com/settings/api-keys>`__ y genera un token de API nuevo.
* ``project_id``: en el Portal de Cherry Servers, abre la sección **Projects**, selecciona tu proyecto y copia su identificador numérico.
* ``ssh_public_key``: ejecuta ``cat ~/.ssh/id_ed25519.pub`` en tu estación de trabajo y pega esa línea completa; nunca copies tu llave privada ``~/.ssh/id_ed25519``.
* ``ssh_key_id``: si tu llave Ed25519 ya está registrada en el portal bajo **SSH Keys**, por ejemplo tras completar la Sección 2, copia aquí su identificador numérico y deja ``ssh_public_key`` vacío para reutilizarla y evitar errores de llave duplicada.

Edita ``terraform.tfvars`` con tus valores:

.. code-block:: hcl

   cherry_auth_token = "TU_TOKEN_DE_API_DE_CHERRY_SERVERS"
   project_id        = 123456
   ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tu_correo@ejemplo.com"
   # ssh_key_id      = "20003"
   server_name       = "0.luanti.linenes.tld"
   server_image      = "centos_stream_10_64bit"
   spot_instance     = false

Inicializa el directorio de trabajo, revisa el plan de ejecución y aplica el manifiesto:

.. code-block:: bash

   tofu init
   tofu plan
   tofu apply

En cuanto Cherry Servers aprovisione la instancia y asigne su dirección IP, OpenTofu mostrará salidas similares a este ejemplo con IP de documentación:

.. code-block:: text

   Outputs:

   connection_string = "203.0.113.50:30000"
   server_ip = "203.0.113.50"
   ssh_command = "ssh root@203.0.113.50"

Ten presente que ``user_data`` se ejecuta de forma asíncrona dentro de la instancia mediante ``cloud-init``: aunque ``tofu apply`` ya terminó, el script de arranque tarda entre 1 y 2 minutos adicionales en instalar paquetes e iniciar Luanti. Sigue el progreso en vivo por SSH:

.. code-block:: bash

   ssh "root@$(tofu output -raw server_ip)" 'tail -f /var/log/user-data.log'

Cuando aparezca ``[+] Despliegue completado con éxito.``, pulsa ``Ctrl+C`` para salir del registro y conéctate desde tu cliente de Luanti usando la dirección de ``connection_string``.

4. Destrucción del Servidor y Control de Costos
===============================================

Para mantener una disciplina estricta de costos en la nube, captura la IP del servidor antes de destruirlo, ejecuta ``tofu destroy``, limpia la entrada correspondiente en ``~/.ssh/known_hosts``, borra tu archivo local con secretos y confirma que el estado quede completamente vacío desde ``01-luanti-tofu/tofu``:

.. code-block:: bash

   # 1. Guardar la IP antes de destruir para limpiar ~/.ssh/known_hosts
   IP_DEL_SERVIDOR=$(tofu output -raw server_ip)

   # 2. Destruir la infraestructura gestionada por OpenTofu
   tofu destroy

   # 3. Retirar la huella SSH del nodo eliminado y borrar credenciales locales
   ssh-keygen -R "${IP_DEL_SERVIDOR}"
   rm -f terraform.tfvars

   # 4. Confirmar que no quedan recursos activos en el estado local
   tofu state list

Confirma escribiendo ``yes`` cuando ``tofu destroy`` lo solicite. Si reutilizaste una clave existente con ``ssh_key_id``, OpenTofu destruirá únicamente el servidor y conservará tu llave SSH registrada en Cherry Servers; si en cambio OpenTofu creó la llave nueva desde ``ssh_public_key``, eliminará ambos recursos:

.. code-block:: text

   Destroy complete! Resources: 2 destroyed.

.. warning::
   **Verifica instancias manuales:** Si creaste un servidor manualmente en el Portal de Cherry Servers durante la Sección 2, entra al panel web y elimínalo también para que no siga generando cargos por hora.

El costo total de completar este laboratorio ronda entre **~$0.02 y $0.03 USD**.

5. Retos de Aprendizaje y Práctica
==================================

Para consolidar lo aprendido y poner a prueba tu criterio en la terminal, completa estos 3 retos prácticos sin soluciones prefabricadas:

#. **Reto 1: Habilitar conectividad en IPv6 nativo**

   * Comprueba mediante ``ip -6 addr show scope global`` si tu instancia dispone de una dirección IPv6 global enrutada y valida si requiere asignación o activación en el portal.
   * Confirma que ``bind_address`` permanezca vacío para escuchar en ``[::]:30000`` en doble pila IPv4/IPv6, o restríngelo a tu dirección IPv6 específica, y verifica que ``firewalld`` permita el tráfico ``30000/udp`` sobre IPv6.
   * Comprueba el socket con ``ss -6ulnp`` y conéctate desde tu cliente de escritorio indicando la dirección IPv6 pública de tu servidor entre corchetes.

#. **Reto 2: Desplegar un segundo mundo con Systemd Parametrizado**

   * Aprovecha la plantilla ``minetest@.service`` para levantar una segunda instancia independiente en el puerto ``30001/udp``, por ejemplo un mundo en modo creativo.
   * Aísla su directorio de datos bajo ``/var/lib/minetest/`` respetando FHS 3.0, crea su configuración en ``/etc/minetest/`` y su archivo de entorno correspondiente en ``/etc/sysconfig/minetest/`` como viste en el Paso F, restaura contextos SELinux y abre el puerto en ``firewalld``. Verifica con ``systemctl --no-pager status`` y ``ss -ulnp`` que ambas instancias operen en paralelo sin conflictos.

#. **Reto 3: Portar la configuración manual a Debian o Ubuntu LTS**

   * Despliega una máquina virtual o servidor con **Debian 13** o **Ubuntu 26.04 LTS** y reproduce de forma manual la instalación y puesta en marcha de Luanti.
   * Documenta las diferencias operativas frente a CentOS Stream 10: gestor de paquetes, rutas de datos y configuración, usuario de sistema, cortafuegos y control de acceso obligatorio.

Referencias Oficiales
=====================

* `CentOS Stream <https://www.centos.org/centos-stream/>`__
* `Documentación oficial de EPEL <https://docs.fedoraproject.org/en-US/epel/>`__
* `Guía oficial de Luanti para administradores de servidores <https://docs.luanti.org/for-server-hosts/>`__
* `Repositorio COPR dherrera/minetest <https://copr.fedorainfracloud.org/coprs/dherrera/minetest/>`__
* `Uso de SELinux en Red Hat Enterprise Linux 10 <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/secure-getting_started_with_selinux>`__
* `Documentación oficial de Firewalld <https://firewalld.org/documentation/>`__
* `Documentación oficial de OpenTofu <https://opentofu.org/docs/>`__

Dudas y Preguntas
=================

¿Encontraste algún detalle técnico, quieres proponer una mejora o tienes dudas sobre alguno de los pasos? Abre un ticket en `Issues en GitLab <https://gitlab.com/renich/cherry-servers/-/issues>`__. ¡Nos vemos en el `Cómo 02: Proxy Inverso con Caddy y Vaultwarden en Podman <../02-caddy-podman/README.rst>`__!

Licencia
========

Este documento y el material educativo de este Cómo se distribuyen bajo los términos de la **GNU Free Documentation License**, GFDL Versión 1.3 o cualquier versión posterior publicada por la Free Software Foundation; sin secciones invariantes ni textos de portada o contraportada.

Consulta el archivo `LICENSE <../LICENSE>`__ en la raíz del repositorio para leer los términos completos.
