=========================================================================
Cómo automatizar y reconstruir servidores con Ansible en CentOS Stream 10
=========================================================================

:Módulo: Cómo 03: Automatización y Reconstrucción con Ansible
:Versión: ``v1.0.0``
:Fecha: ``2026-10-02``
:Directorio: `03-ansible <https://gitlab.com/renich/cherry-servers/-/tree/master/03-ansible>`__
:Licencia: `GFDL-1.3-or-later <../LICENSE>`__
:Tipo de instancia: Cloud VPS 1, Gen 2 con 1 vCore, 1 GB RAM y 20 GB SSD
:Costo por hora: ~$0.015 EUR/hora, ~$0.017 USD/hora
:Tiempo promedio: 1 hora
:Gasto estimado total: ~$0.02 USD

¡Hola! 👋

Te doy una cordial bienvenida a este **tercer Cómo** de nuestra serie práctica de infraestructura y administración de sistemas en Linux para la comunidad de software libre de Latinoamérica y el mundo.

En los dos Cómos anteriores aprendiste los fundamentos de administración a bajo nivel: cómo instalar paquetes RPM, estructurar directorios bajo el estándar **FHS 3.0**, gestionar servicios con **Systemd**, orquestar contenedores con **Podman Quadlets** y gobernar la seguridad con **SELinux en modo Enforcing**.

Sin embargo, configurar servidores ejecutando comandos manualmente por SSH uno por uno no escala en producción. Si un servidor sufre una falla de hardware o necesitas replicar exactamente el mismo servicio en cinco máquinas distintas, el trabajo manual introduce errores humanos, inconsistencias y pérdida de tiempo.

Aquí entra **Ansible**: una herramienta de automatización y gestión de configuraciones **sin agentes**, *agentless*, que opera de forma declarativa e **idempotente** sobre SSH estándar. Todo el laboratorio corre en servidores con **CentOS Stream 10**. Lejos del mito recurrente de que «CentOS murió», CentOS Stream es hoy la rama abierta de entrega continua aguas arriba de **Red Hat Enterprise Linux 10**, con estabilidad ABI/API durante el ciclo mayor, contribución pública transparente, **Python 3** nativo, **SELinux en modo Enforcing** y soporte de primera clase para **EPEL 10**.

Siguiendo nuestra filosofía pedagógica **«Manual Primero, Automatización Después»**, primero comprenderás cómo opera Ansible desde tu nodo de control, construirás un Playbook declarativo paso a paso en un directorio local de práctica, comprobarás la idempotencia y la recuperación ante desvío de configuración o *configuration drift*, y finalmente orquestarás el aprovisionamiento completo del servidor con **OpenTofu**.

1. Prerrequisitos del Laboratorio
=================================

Para realizar esta práctica necesitas dos roles claros: un **nodo de control** desde donde ejecutas Ansible y OpenTofu, y un **nodo servidor objetivo** con CentOS Stream 10 donde se aplicará la configuración.

A. Tu Nodo de Control: Fedora Linux o CentOS Stream 10
------------------------------------------------------

Ejecutarás todo el flujo de automatización, OpenTofu, Ansible Core y OpenSSH, desde tu nodo de control:

#. **Tu estación de trabajo con Fedora Linux, opción recomendada:**

   * Si ya trabajas con **Fedora Linux**, tu propia computadora funciona de forma nativa como nodo de control; **no necesitas rentar un VPS adicional**. Tanto ``ansible-core`` como ``opentofu`` están disponibles directamente en los repositorios oficiales de Fedora.

#. **Un servidor de control CentOS Stream 10 en Cherry Servers, alternativa si usas Windows o macOS:**

   * Si tu equipo personal corre Windows o macOS y prefieres un entorno empresarial Linux puro en la nube, regístrate mediante `este enlace de bienvenida <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__ con el código promocional ``LinuxEnEspanol`` para recibir **$20 USD de crédito de regalo**.
   * En el portal de Cherry Servers, crea una instancia **Cloud VPS 1** con **CentOS Stream 10** y añade tu clave SSH o anota las credenciales iniciales del portal. Localiza su dirección IP pública en la columna **Primary IP** de tu proyecto y conéctate por SSH desde tu terminal como ``root`` para usarla como estación de control.

#. **Una máquina virtual local con CentOS Stream 10:**

   * Si dispones de un hipervisor local como KVM/libvirt con ``virt-manager`` o ``virsh``, VirtualBox o VMware, descarga la imagen oficial de **CentOS Stream 10** y arranca una VM local como estación de control.

B. Usuario Normal sin Privilegios en el Nodo de Control
-------------------------------------------------------

Si trabajas desde tu estación de trabajo local con **Fedora Linux**, ya operas con tu usuario ordinario y puedes avanzar directo a la **Sección 1C**.

Si elegiste una VM o un VPS dedicado con **CentOS Stream 10** como nodo de control y entraste inicialmente como ``root``, crea de inmediato un usuario normal con privilegios administrativos mediante ``sudo``. Como regla fundamental de seguridad en Linux, **nunca debes operar tu estación de control diaria directamente como** ``root``:

.. code-block:: bash

   useradd -m -s /bin/bash estudiante
   passwd estudiante
   usermod -aG wheel estudiante

Inicia sesión con tu usuario normal:

.. code-block:: bash

   su - estudiante

A partir de este punto, **todas las operaciones locales se ejecutan desde tu usuario normal**, reservando ``sudo`` únicamente para instalar paquetes del sistema con DNF.

C. Generación de tu Llave SSH Ed25519 con Frase de Paso
-------------------------------------------------------

Ansible no usa contraseñas interactivas para autenticarse contra los servidores remotos; opera sobre SSH estándar mediante criptografía asimétrica. Si ya creaste una llave Ed25519 en los Cómos 01 o 02, puedes reutilizarla sin sobrescribirla.

Si aún no tienes un par de llaves, genera una llave **Ed25519** protegida por frase de paso o *passphrase*:

.. code-block:: bash

   ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"

#. **Ruta del archivo:** Cuando la herramienta te solicite ``Enter file in which to save the key (/home/estudiante/.ssh/id_ed25519):``, presiona ``Enter`` para aceptar la ruta predeterminada.
#. **Frase de paso o passphrase:** Cuando te pida ``Enter passphrase (empty for no passphrase):``, **escribe una contraseña segura**. Esto cifra tu clave privada con AES-256 en el disco para que nadie pueda usar tu identidad aunque copie el archivo.

Este comando crea dos archivos en ``~/.ssh/``:

* ``~/.ssh/id_ed25519``: tu **llave privada** con permisos estrictos ``0600``; nunca debes compartirla ni subirla a ningún repositorio.
* ``~/.ssh/id_ed25519.pub``: tu **llave pública** con permisos ``0644``; es la única que instalarás en los servidores administrados.

D. Inicio del Demonio ``ssh-agent`` y Carga de tu Llave
-------------------------------------------------------

Al proteger tu llave privada con una frase de paso, cada conexión SSH de Ansible pediría la contraseña en tu terminal, lo cual volvería inviable cualquier automatización.

Para resolverlo sin debilitar la seguridad, Linux incluye ``ssh-agent``, un proceso en segundo plano que mantiene tu llave privada descifrada únicamente en memoria RAM durante tu sesión activa de terminal:

.. code-block:: bash

   # Iniciar el agente SSH en tu sesión actual de la terminal
   eval "$(ssh-agent -s)"

   # Cargar tu llave privada en el agente: ingresa tu frase de paso una sola vez
   ssh-add ~/.ssh/id_ed25519

   # Confirmar que la identidad está cargada en memoria
   ssh-add -l

Verás una salida confirmando que tu llave está disponible:

.. code-block:: text

   256 SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx tu_correo@ejemplo.com (ED25519)

E. El Servidor Objetivo, su Dirección IP y tu Llave Pública
-----------------------------------------------------------

Ahora necesitas el **nodo servidor objetivo** con **CentOS Stream 10** que vas a configurar y asegurar con Ansible. Puedes crear una instancia **Cloud VPS 1** en `Cherry Servers <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__ con el código promocional ``LinuxEnEspanol`` para obtener **$20 USD de crédito**, o levantar una máquina virtual local con CentOS Stream 10.

Antes de ejecutar comandos SSH, obtén la dirección IPv4 pública o accesible de tu servidor objetivo:

* **En Cherry Servers:** abre tu proyecto en el portal web, selecciona la instancia recién creada y copia el valor del campo **Primary IP**.
* **En una máquina virtual local:** inicia sesión en la consola de la VM y consulta su IPv4 activa con ``ip -4 -o addr show scope global``.

En tu **nodo de control**, exporta esa dirección en la variable de entorno ``IP_DEL_SERVIDOR`` para reutilizarla en todo el laboratorio. Reemplaza la dirección de ejemplo ``203.0.113.100`` por la IP real de tu servidor objetivo:

.. code-block:: bash

   export IP_DEL_SERVIDOR="203.0.113.100"

A continuación instala tu llave pública ``~/.ssh/id_ed25519.pub`` en la cuenta ``root`` del servidor objetivo:

* **Si desplegaste el servidor objetivo en el portal de Cherry Servers:** imprime tu clave con ``cat ~/.ssh/id_ed25519.pub`` y regístrala en la sección **SSH Keys** del portal al crear la instancia.
* **Si el servidor objetivo local o recién creado todavía usa acceso temporal por contraseña:** copia tu llave pública con ``ssh-copy-id``:

  .. code-block:: bash

     ssh-copy-id -i ~/.ssh/id_ed25519.pub "root@${IP_DEL_SERVIDOR}"

* **Comprobación de acceso SSH:** prueba la conexión desde tu nodo de control:

  .. code-block:: bash

     ssh "root@${IP_DEL_SERVIDOR}"

  Gracias a ``ssh-agent``, accederás de inmediato como ``root`` sin solicitudes de contraseña. Acepta la huella del servidor al conectar por primera vez y sal de la sesión remota para regresar a tu nodo de control:

  .. code-block:: bash

     exit

F. Instalación de Herramientas en el Nodo de Control
----------------------------------------------------

Instala las herramientas locales en tu nodo de control según tu sistema operativo.

**En Fedora Linux, estación de trabajo local:**

.. code-block:: bash

   sudo dnf -y install ansible-core openssh-clients git-core curl jq opentofu

**En CentOS Stream 10, si usas un nodo de control dedicado:**

.. code-block:: bash

   # 1. Habilitar repositorio EPEL 10 y complementos DNF
   sudo dnf -y install epel-release dnf-plugins-core

   # 2. Instalar Ansible Core y utilidades de red y repositorio
   sudo dnf -y install ansible-core openssh-clients git-core curl jq

   # 3. Instalar OpenTofu mediante el instalador oficial RPM
   curl --proto '=https' --tlsv1.2 -fsSL -o install-opentofu.sh https://get.opentofu.org/install-opentofu.sh
   sudo bash install-opentofu.sh --install-method rpm
   rm -f install-opentofu.sh

Verifica que ambas herramientas respondan correctamente en tu terminal:

.. code-block:: bash

   ansible --version
   tofu version

G. Directorio de Práctica Local para la Construcción Manual
-----------------------------------------------------------

Crea un directorio limpio en tu nodo de control para construir todos los archivos de la **Sección 2** paso a paso desde cero:

.. code-block:: bash

   mkdir -p ~/lab-ansible
   cd ~/lab-ansible

Trabajar primero en ``~/lab-ansible`` evita sobrescribir archivos versionados del repositorio durante la práctica manual. En la **Sección 3** clonarás el repositorio oficial para automatizar la creación del servidor con OpenTofu.

H. Gestión Declarativa de Colecciones con Ansible Galaxy y ``requirements.yaml``
--------------------------------------------------------------------------------

Notarás que en la Sección 1F no instalaste el paquete RPM ``ansible-collection-ansible-posix``. Mantener las colecciones declaradas en ``requirements.yaml`` e instalarlas con ``ansible-galaxy`` en ``~/.ansible/collections`` evita conflictos de sombreado frente a versiones del sistema en ``/usr/share/ansible/collections`` y garantiza reproducibilidad portátil en Fedora, CentOS Stream 10 y flujos de CI/CD.

Declara la dependencia mínima de ``ansible.posix`` en ``requirements.yaml``:

.. code-block:: bash

   cat << 'EOF' > requirements.yaml
   ---
   collections:
     - name: ansible.posix
       version: ">=1.5.0"
   EOF

Instala las colecciones declaradas en tu entorno de usuario con ``ansible-galaxy``:

.. code-block:: bash

   ansible-galaxy collection install -r requirements.yaml

Postura de Privilegios: Acceso Directo como Root Frente a Sudo
--------------------------------------------------------------

En la administración moderna de infraestructura en la nube existe una distinción clave entre tu estación de control y un servidor remoto automatizado:

#. **En tu nodo de control con Fedora Linux o CentOS Stream 10:** operas como un usuario normal sin privilegios y utilizas ``sudo`` solo al modificar paquetes o servicios locales con comandos como ``sudo dnf -y install ...``.
#. **En servidores remotos en la nube:** el acceso por contraseña está deshabilitado mediante ``PermitRootLogin prohibit-password``. Solo quien posea tu llave privada Ed25519 puede abrir una sesión. Crear un usuario intermedio como ``ansible`` o ``admin`` únicamente para darle privilegios universales sin contraseña en ``/etc/sudoers`` con ``NOPASSWD: ALL`` no aporta seguridad real: es **simulación de seguridad** o *security theater* que añade ruido en bitácoras y complejidad sin beneficio.
#. **Verdadero principio de menor privilegio:** la seguridad real vive en los servicios: cada aplicación corre bajo una cuenta de sistema dedicada sin shell interactiva en ``/sbin/nologin``, con permisos estrictos bajo **FHS 3.0** y confinamiento mediante **SELinux**. La cuenta ``root`` se limita a construir y verificar esas fronteras.

2. Construcción y Configuración Manual vía SSH y Ansible CLI, El Núcleo del Aprendizaje
=======================================================================================

Paso A: Fundamentos de Ansible y Arquitectura sin Agentes
---------------------------------------------------------

A diferencia de soluciones tradicionales como Puppet, Chef o SaltStack, Ansible no exige instalar ningún demonio ni agente permanente en el servidor remoto.

Ansible opera bajo el modelo **Push sobre SSH**:

#. Tu nodo de control lee el inventario y el Playbook.
#. Traduce las tareas declarativas a módulos ligeros en Python.
#. Transfiere y ejecuta los módulos en el servidor remoto mediante SSH estándar.
#. Recibe el resultado en JSON estructurado y elimina los archivos temporales al concluir.

El único requisito en el servidor gestionado es contar con **Python 3**, que viene preinstalado por defecto en la imagen oficial de **CentOS Stream 10**.

A partir de aquí, **todas las operaciones se ejecutan desde tu nodo de control**, dentro de ``~/lab-ansible``.

Paso B: Configuración del Entorno de Control y Verificación Estricta de Huellas SSH
-----------------------------------------------------------------------------------

Dentro de ``~/lab-ansible``, crea el archivo de configuración ``ansible.cfg``:

.. code-block:: bash

   cat << 'EOF' > ansible.cfg
   [defaults]
   inventory = inventory.ini
   remote_user = root
   host_key_checking = True
   retry_files_enabled = False
   interpreter_python = auto_silent
   private_key_file = ~/.ssh/id_ed25519

   [privilege_escalation]
   become = False

   [ssh_connection]
   ssh_args = -C -o ControlMaster=auto -o ControlPersist=60s -o IdentitiesOnly=yes
   EOF

Parámetros clave de ``ansible.cfg``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* ``inventory = inventory.ini``: define el archivo de inventario predeterminado para no repetir ``-i inventory.ini`` en cada comando.
* ``remote_user = root``: establece la cuenta remota SSH directamente con tu llave Ed25519.
* ``host_key_checking = True``: mantiene activa la verificación estricta de huellas en ``~/.ssh/known_hosts``. Desactivar esta opción vuelve tu conexión vulnerable a ataques de intermediario, *Man-in-the-Middle* o MITM.
* ``retry_files_enabled = False``: evita que Ansible deje archivos residuales ``.retry`` en tu directorio de trabajo cuando una tarea falla.
* ``interpreter_python = auto_silent``: descubre automáticamente la ruta óptima de Python en el servidor remoto sin emitir advertencias innecesarias.
* ``private_key_file = ~/.ssh/id_ed25519``: indica a Ansible qué llave privada Ed25519 presentar al servidor.
* ``become = False`` bajo ``[privilege_escalation]``: desactiva la elevación por ``sudo``, ya que la sesión SSH opera directamente como ``root`` con llave pública.
* ``ssh_args`` bajo ``[ssh_connection]``: habilita multiplexación de conexiones con ``ControlMaster`` y ``ControlPersist=60s`` para acelerar tareas consecutivas, y añade ``-o IdentitiesOnly=yes`` para que SSH envíe solo la llave configurada y no agote el límite ``MaxAuthTries`` si tu agente contiene varias identidades.

Mantenimiento de ``known_hosts`` con ``ssh-keyscan`` y ``ssh-keygen``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Al mantener ``host_key_checking = True``, tu cliente SSH valida la identidad del servidor remoto antes de transmitir cualquier dato.

Si bien en la Sección 1E aceptaste interactivamente la huella en tu terminal al conectar manualmente, en automatizaciones y despliegues desatendidos el patrón estándar es registrar la clave pública previamente con ``ssh-keyscan`` para evitar bloqueos por confirmaciones interactivas:

.. code-block:: bash

   ssh-keyscan -t ed25519 "${IP_DEL_SERVIDOR}" >> ~/.ssh/known_hosts

.. tip::
   **Consejo de Sysadmin:** En entornos de nube donde creas y destruyes servidores con frecuencia, una dirección IP reciclada puede tener una clave de host anterior guardada. Si alguna vez ves ``WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!``, no desactives la verificación; purga la entrada obsoleta con:

   .. code-block:: bash

      ssh-keygen -R "${IP_DEL_SERVIDOR}"

   Y vuelve a ejecutar ``ssh-keyscan`` para registrar la identidad del nuevo servidor.

Ahora crea el archivo de inventario ``inventory.ini``. Usa un heredoc sin comillas en ``EOF`` para que Bash inserte automáticamente el valor de ``${IP_DEL_SERVIDOR}`` que exportaste en la Sección 1E:

.. code-block:: bash

   cat << EOF > inventory.ini
   [webservers]
   cherry-node ansible_host=${IP_DEL_SERVIDOR} ansible_user=root
   EOF

Observa que ``ansible_python_interpreter`` no se fija en el inventario: al omitirlo, dejas que ``interpreter_python = auto_silent`` en ``ansible.cfg`` descubra automáticamente ``/usr/bin/python3`` en el servidor objetivo.

Paso C: Comprobación de Conectividad y Módulos Ad-Hoc
-----------------------------------------------------

Ansible permite ejecutar comandos puntuales denominados **ad-hoc** sin escribir un Playbook completo.

Prueba la conectividad utilizando el nombre completo de colección **FQCN** ``ansible.builtin.ping``:

.. code-block:: bash

   ansible -m ansible.builtin.ping webservers

.. note::
   **Aclaración importante:** El módulo ``ping`` de Ansible **no envía paquetes ICMP de red**. Ejecuta un micro-script en Python en el nodo remoto para comprobar la autenticación SSH, la integridad del canal y la disponibilidad del intérprete Python.

La respuesta exitosa se verá así:

.. code-block:: text

   cherry-node | SUCCESS => {
       "ansible_facts": {
           "discovered_interpreter_python": "/usr/bin/python3"
       },
       "changed": false,
       "ping": "pong"
   }

Ahora inspecciona la recolección automática de variables del sistema o *facts* mediante el módulo ``ansible.builtin.setup``:

.. code-block:: bash

   ansible -a "filter=ansible_distribution*" -m ansible.builtin.setup webservers

Ansible reportará los hechos descubiertos del sistema operativo en tiempo real:

.. code-block:: text

   cherry-node | SUCCESS => {
       "ansible_facts": {
           "ansible_distribution": "CentOS Stream",
           "ansible_distribution_major_version": "10",
           "ansible_distribution_version": "10"
       },
       "changed": false
   }

El Manual de Componentes y Módulos: ``ansible-doc``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Antes de escribir tu Playbook, aprovecha el sistema de documentación integrado directamente en tu terminal:

* **Consultar el manual completo de un módulo:**

  .. code-block:: bash

     ansible-doc ansible.posix.selinux

  Despliega una vista análoga a las páginas ``man`` con descripción, requisitos, parámetros, valores predeterminados y ejemplos de uso.

* **Obtener un fragmento conciso listo para usar con** ``-s`` **:**

  .. code-block:: bash

     ansible-doc -s ansible.posix.selinux
     ansible-doc -s ansible.posix.firewalld
     ansible-doc -s ansible.builtin.dnf

  La bandera ``-s`` imprime la estructura YAML mínima del módulo con los tipos de datos esperados y marcas de campos obligatorios ``# (required)``, ideal para consultar sintaxis exacta mientras escribes tus tareas.

* **Documentación oficial del proyecto en la web:**

  * Colección `ansible.posix <https://docs.ansible.com/ansible/latest/collections/ansible/posix/>`__: módulos para cortafuegos con ``firewalld``, políticas de ``selinux``, parámetros del kernel con ``sysctl`` y montajes.
  * Colección `ansible.builtin <https://docs.ansible.com/ansible/latest/collections/ansible/builtin/>`__: módulos esenciales del núcleo como ``dnf``, ``systemd_service``, ``file``, ``template``, ``copy``, ``user`` y ``group``.

Paso D: Creación del Playbook Declarativo e Idempotente en ``playbook.yaml``
----------------------------------------------------------------------------

Un **Playbook** es un archivo YAML donde describes el **estado deseado** de tu infraestructura. En lugar de dictar pasos imperativos, declaras condiciones finales: qué paquetes deben estar instalados, qué usuarios deben existir, qué permisos y contextos SELinux deben aplicarse y qué servicios deben quedar activos.

Para este laboratorio automatizarás el despliegue de un servicio web bajo **FHS 3.0** en ``/srv/webapp``, con Nginx, sincronización horaria mediante Chrony, reglas en Firewalld y **SELinux en modo Enforcing**.

Primero crea el directorio para tus plantillas Jinja2:

.. code-block:: bash

   mkdir -p templates

Crea la plantilla de configuración de Nginx en ``templates/webapp.conf.j2``:

.. code-block:: bash

   cat << 'EOF' > templates/webapp.conf.j2
   # =============================================================================
   # Configuración de Nginx para Servicio Web FHS 3.0 (/srv/webapp)
   # Gestionado de forma declarativa con Ansible en CentOS Stream 10
   # =============================================================================

   server {
       listen 80 default_server;
       listen [::]:80 default_server;
       server_name _;

       root /srv/webapp/public;
       index index.html;

       server_tokens off;

       location / {
           try_files $uri $uri/ =404;
       }

       location = /favicon.ico {
           log_not_found off;
           access_log off;
       }
   }
   EOF

Directivas clave de ``templates/webapp.conf.j2``:

* ``listen 80 default_server`` y ``listen [::]:80 default_server``: atienden tráfico HTTP en IPv4 e IPv6 como servidor predeterminado.
* ``server_name _``: comodín estándar de Nginx que acepta peticiones directas por dirección IP sin depender todavía de un dominio DNS.
* ``root /srv/webapp/public`` e ``index index.html``: señalan la raíz pública de datos bajo FHS 3.0.
* ``server_tokens off``: oculta la versión exacta de Nginx en cabeceras HTTP y páginas de error para reducir la información expuesta ante escaneos.
* ``try_files $uri $uri/ =404``: sirve archivos estáticos existentes o devuelve ``404`` de inmediato.
* ``location = /favicon.ico``: silencia registros innecesarios cuando los navegadores piden automáticamente el icono del sitio.

Crea la plantilla HTML en ``templates/index.html.j2``. Observa que utiliza únicamente hechos estables del host, como la distribución y la IPv4 principal, para que la página sea informativa sin cambiar su suma de verificación en corridas posteriores:

.. code-block:: bash

   cat << 'EOF' > templates/index.html.j2
   <!DOCTYPE html>
   <html lang="es">
   <head>
       <meta charset="utf-8">
       <meta name="viewport" content="width=device-width, initial-scale=1">
       <title>Servidor Automatizado con Ansible: Cómo 03</title>
       <style>
           :root {
               --bg-color: #1e1e2e;
               --card-bg: #181825;
               --text-color: #cdd6f4;
               --subtext: #a6adc8;
               --accent: #f38ba8;
               --accent-green: #a6e3a1;
               --accent-blue: #89b4fa;
               --border: #313244;
           }
           body {
               font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace;
               background-color: var(--bg-color);
               color: var(--text-color);
               margin: 0;
               padding: 2rem;
               display: flex;
               justify-content: center;
               align-items: center;
               min-height: 100vh;
               box-sizing: border-box;
           }
           .container {
               background-color: var(--card-bg);
               border: 1px solid var(--border);
               border-radius: 12px;
               padding: 2.5rem;
               max-width: 680px;
               width: 100%;
               box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
           }
           h1 {
               color: var(--accent);
               margin-top: 0;
               font-size: 1.8rem;
               display: flex;
               align-items: center;
               gap: 0.5rem;
           }
           p.subtitle {
               color: var(--subtext);
               margin-bottom: 2rem;
               font-size: 1rem;
               line-height: 1.5;
           }
           .status-badge {
               display: inline-block;
               background: rgba(166, 227, 161, 0.15);
               color: var(--accent-green);
               padding: 0.25rem 0.75rem;
               border-radius: 9999px;
               font-size: 0.85rem;
               font-weight: 600;
               margin-bottom: 1.5rem;
               border: 1px solid rgba(166, 227, 161, 0.3);
           }
           .grid {
               display: grid;
               grid-template-columns: 1fr 1fr;
               gap: 1rem;
               margin-bottom: 2rem;
           }
           .item {
               background-color: rgba(255, 255, 255, 0.02);
               border: 1px solid var(--border);
               padding: 1rem;
               border-radius: 8px;
           }
           .label {
               font-size: 0.75rem;
               text-transform: uppercase;
               letter-spacing: 0.05em;
               color: var(--subtext);
               margin-bottom: 0.25rem;
           }
           .value {
               font-size: 1.05rem;
               font-weight: 600;
               color: var(--accent-blue);
               word-break: break-all;
           }
           .footer {
               border-top: 1px solid var(--border);
               padding-top: 1.5rem;
               font-size: 0.85rem;
               color: var(--subtext);
               text-align: center;
           }
           .footer a {
               color: var(--accent);
               text-decoration: none;
           }
           .footer a:hover {
               text-decoration: underline;
           }
       </style>
   </head>
   <body>
       <div class="container">
           <div class="status-badge">● Sistema Idempotente y Convergente &bull; Versión {{ webapp_version }}</div>
           <h1>Servidor Desplegado con Ansible</h1>
           <p class="subtitle">
               Este nodo fue configurado y asegurado de forma totalmente declarativa mediante Ansible en
               <strong>CentOS Stream 10</strong> sobre infraestructura de <strong>Cherry Servers</strong>.
           </p>

           <div class="grid">
               <div class="item">
                   <div class="label">Nombre de Host</div>
                   <div class="value">{{ ansible_facts['hostname'] }}</div>
               </div>
               <div class="item">
                   <div class="label">Distribución</div>
                   <div class="value">{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}</div>
               </div>
               <div class="item">
                   <div class="label">Kernel</div>
                   <div class="value">{{ ansible_facts['kernel'] }}</div>
               </div>
               <div class="item">
                   <div class="label">Arquitectura y CPUs</div>
                   <div class="value">{{ ansible_facts['architecture'] }} ({{ ansible_facts['processor_vcpus'] }} vCPUs)</div>
               </div>
               <div class="item">
                   <div class="label">Memoria Total</div>
                   <div class="value">{{ ansible_facts['memtotal_mb'] }} MB</div>
               </div>
               <div class="item">
                   <div class="label">Dirección IPv4</div>
                   <div class="value">{{ ansible_facts['default_ipv4']['address'] }}</div>
               </div>
           </div>

           <div class="footer">
               Cómo 03: Serie Educativa de Infraestructura en Linux &bull;
               <a href="https://gitlab.com/renich/cherry-servers" target="_blank" rel="noopener">Repositorio en GitLab</a>
           </div>
       </div>
   </body>
   </html>
   EOF

Anatomía y Construcción del Playbook Bloque a Bloque
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

En lugar de copiar un archivo monolítico sin entenderlo, revisa la anatomía del Playbook dividida en seis bloques claros:

Bloque 1: Cabecera del Play y Variables Globales en ``vars``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Todo Playbook inicia declarando el grupo objetivo ``hosts: webservers``, activando ``gather_facts: true`` y aislando los parámetros en ``vars`` para no dejar valores fijos dispersos en las tareas. Incluye ``curl`` en el servidor objetivo para facilitar pruebas HTTP locales desde el propio nodo cuando necesites diagnosticar el servicio:

.. code-block:: yaml

   ---
   - name: Aprovisionar y asegurar servidor web FHS 3.0 en CentOS Stream 10
     hosts: webservers
     gather_facts: true

     vars:
       webapp_service_user: "webapp"
       webapp_service_group: "webapp"
       webapp_root_dir: "/srv/webapp"
       webapp_public_dir: "/srv/webapp/public"
       webapp_version: "1.0.0"
       required_packages:
         - epel-release
         - nginx
         - firewalld
         - chrony
         - curl

Bloque 2: Paquetes del Sistema y Sincronización de Tiempo con Chrony
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Instalas todos los paquetes en una sola transacción DNF. Pasar una lista directa a ``name:`` es mucho más rápido que usar ``loop:``, pues DNF resuelve todas las dependencias en una única ejecución:

.. code-block:: yaml

     tasks:
       - name: Instalar paquetes esenciales del sistema y repositorio EPEL 10
         ansible.builtin.dnf:
           name: "{{ required_packages }}"
           state: present

       - name: Garantizar que el servicio de sincronización de tiempo Chrony esté activo
         ansible.builtin.systemd_service:
           name: chronyd
           state: started
           enabled: true

Bloque 3: Usuario de Sistema y Jerarquía FHS 3.0
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Creas una cuenta dedicada para aislar el contenido web bajo ``webapp`` sin shell interactiva en ``/sbin/nologin``:

* ``system: true`` asigna un UID/GID dentro del rango reservado de cuentas de sistema, inferior a ``1000``, separado de usuarios humanos.
* ``useradd -m`` crea ``/srv/webapp`` con permisos ``0700`` por defecto; por eso declaras explícitamente ``mode: '0750'`` para que el grupo ``webapp`` pueda recorrer la jerarquía.
* ``seuser: system_u`` aplica la identidad de usuario SELinux propia de archivos administrados por servicios del sistema, mientras ``setype: httpd_sys_content_t`` autoriza a Nginx a leer el contenido estático.

.. code-block:: yaml

       - name: Crear grupo de sistema dedicado bajo estándar FHS 3.0
         ansible.builtin.group:
           name: "{{ webapp_service_group }}"
           state: present
           system: true

       - name: Crear usuario de sistema sin shell interactiva
         ansible.builtin.user:
           name: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           shell: /sbin/nologin
           home: "{{ webapp_root_dir }}"
           create_home: true
           system: true
           state: present

       - name: Crear directorio base del servicio bajo estándar FHS 3.0
         ansible.builtin.file:
           path: "{{ webapp_root_dir }}"
           state: directory
           owner: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           mode: '0750'
           seuser: system_u
           setype: httpd_sys_content_t

       - name: Crear estructura de directorios web con permisos 0750 y contexto SELinux
         ansible.builtin.file:
           path: "{{ webapp_public_dir }}"
           state: directory
           owner: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           mode: '0750'
           seuser: system_u
           setype: httpd_sys_content_t

Bloque 4: Despliegue de Plantillas y Configuración de Nginx
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Despliegas la página HTML y el bloque de servidor en ``/etc/nginx/conf.d/webapp.conf``, distinguiendo tres detalles críticos:

* ``httpd_config_t`` frente a ``httpd_sys_content_t``: los archivos de configuración en ``/etc/nginx/conf.d/`` llevan ``httpd_config_t``, mientras el contenido estático servido al público en ``/srv/webapp/public`` lleva ``httpd_sys_content_t``.
* ``changed_when: false`` en ``/usr/sbin/nginx -t``: indica a Ansible que esta comprobación de sintaxis es de solo lectura y no altera el servidor, preservando ``changed=0`` en corridas subsecuentes.
* ``append: true`` al agregar ``nginx`` al grupo ``webapp``: añade el grupo secundario sin sobrescribir ni borrar otros grupos a los que ya pertenezca el usuario ``nginx``.

.. code-block:: yaml

       - name: Desplegar panel informativo dinámico HTML
         ansible.builtin.template:
           src: index.html.j2
           dest: "{{ webapp_public_dir }}/index.html"
           owner: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           mode: '0640'
           seuser: system_u
           setype: httpd_sys_content_t

       - name: Desplegar configuración de bloque de servidor Nginx
         ansible.builtin.template:
           src: webapp.conf.j2
           dest: /etc/nginx/conf.d/webapp.conf
           owner: root
           group: root
           mode: '0644'
           seuser: system_u
           setype: httpd_config_t
         notify: Recargar servicio Nginx

       - name: Validar sintaxis global de Nginx tras desplegar bloque de servidor
         ansible.builtin.command:
           cmd: /usr/sbin/nginx -t
         changed_when: false

       - name: Agregar usuario nginx al grupo complementario de webapp para recorrido de directorios
         ansible.builtin.user:
           name: nginx
           groups: "{{ webapp_service_group }}"
           append: true
         notify: Recargar servicio Nginx

Bloque 5: Políticas de Seguridad con SELinux y Firewalld
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Aseguras la postura de seguridad y levantas ``firewalld`` antes de iniciar ``nginx``:

* ``policy: targeted`` es la política predeterminada de CentOS Stream 10 y RHEL: confina demonios de red expuestos como Nginx sin estorbar sesiones interactivas de administración.
* ``permanent: true`` junto con ``immediate: true`` persiste la regla del servicio ``http`` en disco para sobrevivir reinicios y la aplica al instante sobre el cortafuegos activo.

.. code-block:: yaml

       - name: Garantizar postura de SELinux en modo Enforcing con política targeted
         ansible.posix.selinux:
           policy: targeted
           state: enforcing

       - name: Asegurar que el cortafuegos firewalld esté activo y habilitado
         ansible.builtin.systemd_service:
           name: firewalld
           state: started
           enabled: true

       - name: Habilitar servicio HTTP en firewalld de manera permanente e inmediata
         ansible.posix.firewalld:
           service: http
           permanent: true
           immediate: true
           state: enabled

       - name: Asegurar que el servicio Nginx esté iniciado y habilitado en el arranque
         ansible.builtin.systemd_service:
           name: nginx
           state: started
           enabled: true

Bloque 6: Manejadores de Estado o ``handlers``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Los manejadores se ejecutan una sola vez al final del Play únicamente si alguna tarea los notificó con ``notify``, evitando recargas innecesarias cuando nada cambió:

.. code-block:: yaml

     handlers:
       - name: Recargar servicio Nginx
         ansible.builtin.systemd_service:
           name: nginx
           state: reloaded

Consolidación y Verificación del Archivo ``playbook.yaml``
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Consolida los seis bloques en ``~/lab-ansible/playbook.yaml`` respetando estrictamente la indentación de dos espacios:

.. code-block:: bash

   cat << 'EOF' > playbook.yaml
   ---
   - name: Aprovisionar y asegurar servidor web FHS 3.0 en CentOS Stream 10
     hosts: webservers
     gather_facts: true

     vars:
       webapp_service_user: "webapp"
       webapp_service_group: "webapp"
       webapp_root_dir: "/srv/webapp"
       webapp_public_dir: "/srv/webapp/public"
       webapp_version: "1.0.0"
       required_packages:
         - epel-release
         - nginx
         - firewalld
         - chrony
         - curl

     tasks:
       - name: Instalar paquetes esenciales del sistema y repositorio EPEL 10
         ansible.builtin.dnf:
           name: "{{ required_packages }}"
           state: present

       - name: Garantizar que el servicio de sincronización de tiempo Chrony esté activo
         ansible.builtin.systemd_service:
           name: chronyd
           state: started
           enabled: true

       - name: Crear grupo de sistema dedicado bajo estándar FHS 3.0
         ansible.builtin.group:
           name: "{{ webapp_service_group }}"
           state: present
           system: true

       - name: Crear usuario de sistema sin shell interactiva
         ansible.builtin.user:
           name: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           shell: /sbin/nologin
           home: "{{ webapp_root_dir }}"
           create_home: true
           system: true
           state: present

       - name: Crear directorio base del servicio bajo estándar FHS 3.0
         ansible.builtin.file:
           path: "{{ webapp_root_dir }}"
           state: directory
           owner: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           mode: '0750'
           seuser: system_u
           setype: httpd_sys_content_t

       - name: Crear estructura de directorios web con permisos 0750 y contexto SELinux
         ansible.builtin.file:
           path: "{{ webapp_public_dir }}"
           state: directory
           owner: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           mode: '0750'
           seuser: system_u
           setype: httpd_sys_content_t

       - name: Desplegar panel informativo dinámico HTML
         ansible.builtin.template:
           src: index.html.j2
           dest: "{{ webapp_public_dir }}/index.html"
           owner: "{{ webapp_service_user }}"
           group: "{{ webapp_service_group }}"
           mode: '0640'
           seuser: system_u
           setype: httpd_sys_content_t

       - name: Desplegar configuración de bloque de servidor Nginx
         ansible.builtin.template:
           src: webapp.conf.j2
           dest: /etc/nginx/conf.d/webapp.conf
           owner: root
           group: root
           mode: '0644'
           seuser: system_u
           setype: httpd_config_t
         notify: Recargar servicio Nginx

       - name: Validar sintaxis global de Nginx tras desplegar bloque de servidor
         ansible.builtin.command:
           cmd: /usr/sbin/nginx -t
         changed_when: false

       - name: Agregar usuario nginx al grupo complementario de webapp para recorrido de directorios
         ansible.builtin.user:
           name: nginx
           groups: "{{ webapp_service_group }}"
           append: true
         notify: Recargar servicio Nginx

       - name: Garantizar postura de SELinux en modo Enforcing con política targeted
         ansible.posix.selinux:
           policy: targeted
           state: enforcing

       - name: Asegurar que el cortafuegos firewalld esté activo y habilitado
         ansible.builtin.systemd_service:
           name: firewalld
           state: started
           enabled: true

       - name: Habilitar servicio HTTP en firewalld de manera permanente e inmediata
         ansible.posix.firewalld:
           service: http
           permanent: true
           immediate: true
           state: enabled

       - name: Asegurar que el servicio Nginx esté iniciado y habilitado en el arranque
         ansible.builtin.systemd_service:
           name: nginx
           state: started
           enabled: true

     handlers:
       - name: Recargar servicio Nginx
         ansible.builtin.systemd_service:
           name: nginx
           state: reloaded
   EOF

.. note::
   **Nota técnica sobre SELinux con** ``setype`` **frente a** ``semanage fcontext`` **:** En este Playbook utilizas ``setype: httpd_sys_content_t`` en los módulos ``file`` y ``template``. Esto aplica el contexto directamente sobre los atributos extendidos ``xattr`` del inodo, de manera análoga a ``chcon``, sin exigir paquetes adicionales de políticas en el servidor gestionado. Si alguien ejecutara ``restorecon -Rv /srv/webapp``, la política base devolvería ``/srv`` a ``var_t``. En el Reto 4 aprenderás a registrar reglas persistentes con ``semanage fcontext`` o ``community.general.sefcontext``.

Verifica la sintaxis del Playbook sin ejecutarlo:

.. code-block:: bash

   ansible-playbook --syntax-check playbook.yaml

Si no hay errores, la salida confirmará: ``playbook: playbook.yaml``.

Paso E: Ejecución del Playbook y Prueba de Idempotencia
-------------------------------------------------------

Ejecuta el Playbook por primera vez:

.. code-block:: bash

   ansible-playbook playbook.yaml

Ansible ejecutará cada tarea en orden y al finalizar imprimirá el resumen ``PLAY RECAP``:

.. code-block:: text

   PLAY RECAP *********************************************************************
   cherry-node   : ok=16   changed=13   unreachable=0    failed=0    skipped=0

El conteo exacto de ``changed`` en la primera ejecución puede variar ligeramente según qué servicios como ``chronyd`` o ``firewalld`` vengan ya activos en tu imagen base; lo relevante es que las tareas aplicadas alcancen el estado deseado sin errores y la segunda corrida converja a cero cambios.

Comprueba la respuesta HTTP desde tu nodo de control respetando tiempos límite estrictos en ``curl``:

.. code-block:: bash

   curl -fsS --connect-timeout 5 --max-time 10 "http://${IP_DEL_SERVIDOR}" | grep "Servidor Desplegado con Ansible"

Verifica también la postura de seguridad, contextos SELinux, ausencia de denegaciones AVC, cortafuegos y servicios activos directamente en el servidor objetivo:

.. code-block:: bash

   # Confirmar modo Enforcing de SELinux con módulo ad-hoc
   ansible -m ansible.builtin.command -a "getenforce" webservers

   # Inspeccionar permisos FHS 3.0, etiquetas SELinux, bitácora AVC, firewalld y servicios
   ssh "root@${IP_DEL_SERVIDOR}" 'ls -laZ /srv/webapp /srv/webapp/public /etc/nginx/conf.d/webapp.conf'
   ssh "root@${IP_DEL_SERVIDOR}" 'ausearch -m AVC,USER_AVC -ts recent </dev/null || true'
   ssh "root@${IP_DEL_SERVIDOR}" 'firewall-cmd --list-services && systemctl is-active nginx chronyd firewalld'

Confirmarás ``Enforcing`` en ``getenforce``, contextos ``httpd_sys_content_t`` bajo ``/srv/webapp`` y ``httpd_config_t`` en ``/etc/nginx/conf.d/webapp.conf``, salida ``<no matches>`` en ``ausearch`` indicando cero denegaciones SELinux, el servicio ``http`` listado en ``firewall-cmd`` y estado ``active`` en los tres demonios.

La Prueba de Fuego: Idempotencia Absoluta
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Vuelve a ejecutar exactamente el mismo Playbook:

.. code-block:: bash

   ansible-playbook playbook.yaml

Observa atentamente el resumen ``PLAY RECAP``:

.. code-block:: text

   PLAY RECAP *********************************************************************
   cherry-node   : ok=15   changed=0    unreachable=0    failed=0    skipped=0

``changed=0``. Esto demuestra la **idempotencia** real: el servidor ya coincide con la declaración de estado, por lo que Ansible no reescribe archivos, no dispara el manejador y no reinicia ningún servicio innecesariamente.

Paso F: Reconstrucción y Recuperación ante Desvío o *Configuration Drift*
-------------------------------------------------------------------------

El desvío de configuración o *drift* ocurre cuando alguien edita o borra un archivo a mano por SSH, detiene un servicio por accidente o una actualización rompe un ajuste.

Provoca un desvío controlado en el servidor objetivo:

.. code-block:: bash

   # Detener Nginx y borrar su archivo de configuración a propósito
   ssh "root@${IP_DEL_SERVIDOR}" "systemctl stop nginx && rm -f /etc/nginx/conf.d/webapp.conf"

Si consultas el servicio ahora con ``curl -fsS --connect-timeout 5 --max-time 10 "http://${IP_DEL_SERVIDOR}"``, fallará con error de conexión rechazada.

En lugar de reconstruir a mano qué faltaba, vuelve a ejecutar tu Playbook:

.. code-block:: bash

   ansible-playbook playbook.yaml

Ansible detectará que falta ``/etc/nginx/conf.d/webapp.conf`` y que ``nginx`` está detenido. Aplicará exactamente **tres cambios**: recrear el archivo de configuración con su contexto SELinux ``httpd_config_t``, iniciar el servicio ``nginx`` y ejecutar el manejador ``Recargar servicio Nginx`` notificado por la plantilla restaurada:

.. code-block:: text

   PLAY RECAP *********************************************************************
   cherry-node   : ok=16   changed=3    unreachable=0    failed=0    skipped=0

Verifica las cabeceras HTTP con ``curl``:

.. code-block:: bash

   curl -fsS --connect-timeout 5 --max-time 10 -I "http://${IP_DEL_SERVIDOR}"

El servidor responderá de nuevo con ``HTTP/1.1 200 OK``.

Paso G: Simulación Segura en Modo Prueba y Diagnóstico Operativo
----------------------------------------------------------------

Antes de aplicar modificaciones de tu Playbook en servidores productivos, ejecuta una simulación sin alterar el sistema con ``--check`` combinada con ``--diff`` para inspeccionar línea por línea cualquier cambio pendiente en archivos o plantillas:

.. code-block:: bash

   ansible-playbook --check --diff playbook.yaml

Cuando necesites depurar tráfico o recargas de Nginx en el nodo gestionado, inspecciona directamente su bitácora estructurada en ``systemd-journald``:

.. code-block:: bash

   ssh "root@${IP_DEL_SERVIDOR}" 'journalctl -u nginx -n 20 --no-pager'

Paso H: Mantenimiento Continuo y Actualizaciones Automáticas con DNF5
---------------------------------------------------------------------

En **CentOS Stream 10**, **DNF5** declara ``/etc/dnf/automatic.conf`` como archivo ``%ghost``: no existe en disco hasta copiar la plantilla de referencia instalada en ``/usr/share/dnf5/dnf5-plugins/automatic.conf``. Activa las actualizaciones desatendidas en el servidor objetivo protegiendo esa condición antes de editar la configuración:

.. code-block:: bash

   ssh "root@${IP_DEL_SERVIDOR}" bash -s << 'EOF'
   set -euo pipefail
   dnf -y install dnf-automatic
   [[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
   sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
   systemctl --now enable dnf-automatic.timer
   systemctl --no-pager status dnf-automatic.timer
   EOF

3. Automatización Declarativa con OpenTofu e Infraestructura como Código
========================================================================

Hasta ahora configuraste el sistema operativo sobre un servidor creado manualmente. En la ingeniería moderna de infraestructura, la creación de la máquina virtual también se define como código reproducible.

**OpenTofu** y **Ansible** se complementan por diseño:

* **OpenTofu** aprovisiona el cómputo, la red y el acceso SSH en la nube.
* **Ansible** orquesta paquetes, usuarios, permisos FHS 3.0, SELinux, cortafuegos y servicios dentro del sistema operativo.

Instalación y Versión de OpenTofu
---------------------------------

En la Sección 1F instalaste **OpenTofu** en tu nodo de control. Este módulo requiere ``>= 1.8.0``; confirma tu versión actual con ``tofu version`` antes de continuar.

Clonar el Repositorio y Explorar Manifiestos
--------------------------------------------

Regresa a tu directorio personal, clona el repositorio oficial de la serie e ingresa a la carpeta del Cómo 03:

.. code-block:: bash

   cd ~
   git clone https://gitlab.com/renich/cherry-servers.git
   cd cherry-servers/03-ansible

Si llegaste directo a esta sección sin ejecutar la Sección 1H, instala primero la colección requerida con ``ansible-galaxy collection install -r requirements.yaml``.

Explora los archivos versionados de este módulo:

* `tofu/provider.tf <tofu/provider.tf>`__: fija OpenTofu ``>= 1.8.0`` y el proveedor oficial ``cherryservers/cherryservers ~> 1.5.3``.
* `tofu/variables.tf <tofu/variables.tf>`__: define el token de API, ``project_id``, región, plan ``B1-1-1gb-20s-shared``, imagen CentOS Stream 10, ``ssh_public_key`` y el identificador opcional ``ssh_key_id``.
* `tofu/main.tf <tofu/main.tf>`__: registra o reutiliza tu llave SSH Ed25519 con precondición de validación y aprovisiona la instancia limpia. A diferencia de otros Cómos de la serie, ``tofu/main.tf`` omite intencionalmente ``user_data``, porque aquí OpenTofu entrega solo la máquina virtual base y delega toda la configuración del sistema operativo a Ansible por SSH.
* `tofu/outputs.tf <tofu/outputs.tf>`__: expone ``server_ip``, ``ssh_command``, ``web_url`` y ``ansible-playbook playbook.yaml``.
* `playbook.yaml <playbook.yaml>`__: el Playbook declarativo completo equivalente al que construiste paso a paso en la Sección 2.

Configurar Variables Locales y Desplegar con ``tofu apply``
-----------------------------------------------------------

Ingresa al subdirectorio ``tofu/``, copia la plantilla de variables y restringe sus permisos a ``0600`` para proteger tu token de API:

.. code-block:: bash

   cd tofu
   cp terraform.tfvars.example terraform.tfvars
   chmod 600 terraform.tfvars

Antes de editar ``terraform.tfvars``, reúne cada valor desde su fuente oficial:

* ``cherry_auth_token``: genéralo en `API Keys del Portal de Cherry Servers <https://portal.cherryservers.com/settings/api-keys>`__ bajo **Settings** -> **API Keys** y cópialo al crearlo.
* ``project_id``: entra en el portal a **Projects** y copia el identificador numérico de tu proyecto activo, por ejemplo ``123456``.
* ``ssh_public_key``: copia la salida completa de ``cat ~/.ssh/id_ed25519.pub``.
* ``ssh_key_id``: campo opcional; si tu clave pública Ed25519 ya fue registrada en el portal bajo **SSH Keys** durante la práctica manual de la Sección 1E, descomenta ``ssh_key_id`` con su ID numérico para reutilizarla y evitar un error de clave duplicada.

Edita ``terraform.tfvars`` con tus datos reales:

.. code-block:: hcl

   cherry_auth_token = "TU_API_TOKEN_AQUI"
   project_id        = 123456
   region            = "LT-Siauliai"
   server_plan       = "B1-1-1gb-20s-shared"
   server_image      = "centos_stream_10_64bit"
   server_name       = "0.ansible.linenes.tld"
   ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tu_correo@ejemplo.com"
   # ssh_key_id      = "20003"
   spot_instance     = false

Inicializa los proveedores, valida los manifiestos y revisa el plan de ejecución:

.. code-block:: bash

   tofu init
   tofu validate
   tofu plan

.. warning::
   **Disciplina de costos antes de aplicar:** ejecutar ``tofu apply`` crea un servidor real facturable por hora en tu cuenta de Cherry Servers, aproximadamente ``~$0.015 EUR/hora`` para ``Cloud VPS 1``. Destruye siempre el laboratorio en la **Sección 4** al terminar tus pruebas.

Despliega la instancia:

.. code-block:: bash

   tofu apply

Confirma escribiendo ``yes``. En alrededor de un minuto OpenTofu aprovisionará el servidor e imprimirá salidas como las siguientes, donde ``203.0.113.100`` es solo un valor ilustrativo:

.. code-block:: text

   Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

   Outputs:

   ansible_playbook_command = "ansible-playbook playbook.yaml"
   server_ip = "203.0.113.100"
   ssh_command = "ssh root@203.0.113.100"
   web_url = "http://203.0.113.100"

Regresa a la raíz del módulo ``03-ansible/``, captura dinámicamente la IP asignada en ``IP_DEL_SERVIDOR``, espera hasta que el servidor SSH esté listo, registra su clave de host Ed25519, actualiza ``inventory.ini``, ejecuta el Playbook y verifica el servicio web:

.. code-block:: bash

   cd ..
   export IP_DEL_SERVIDOR="$(tofu -chdir=tofu output -raw server_ip)"

   # Esperar hasta que sshd responda con su clave de host Ed25519
   until ssh-keyscan -t ed25519 "${IP_DEL_SERVIDOR}" 2>/dev/null | grep -q ssh-ed25519; do sleep 5; done
   ssh-keyscan -t ed25519 "${IP_DEL_SERVIDOR}" >> ~/.ssh/known_hosts

   # Actualizar el inventario y aprovisionar el sistema completo con Ansible
   sed -i "s/ansible_host=[^ ]*/ansible_host=${IP_DEL_SERVIDOR}/" inventory.ini
   ansible-playbook playbook.yaml

   # Comprobar la respuesta HTTP del nuevo nodo
   curl -fsS --connect-timeout 5 --max-time 10 "http://${IP_DEL_SERVIDOR}" | grep "Servidor Desplegado con Ansible"

En menos de un minuto tendrás un servidor completamente nuevo, configurado, endurecido e idéntico al que construiste en tu práctica manual.

4. Destrucción del Servidor y Control de Costos
===============================================

Una regla esencial en infraestructura en la nube es la **disciplina de costos**. Al concluir tus pruebas y retos, captura primero la IP asignada para limpiar ``known_hosts``, destruye los recursos creados por OpenTofu, elimina tus credenciales locales y verifica que el estado quede vacío:

.. code-block:: bash

   # Desde cherry-servers/03-ansible/: capturar IP antes de destruir el estado
   export IP_DEL_SERVIDOR="$(tofu -chdir=tofu output -raw server_ip)"

   # Destruir la infraestructura administrada por OpenTofu
   tofu -chdir=tofu destroy

   # Purgar la clave de host, eliminar credenciales locales y confirmar estado vacío
   ssh-keygen -R "${IP_DEL_SERVIDOR}"
   rm -f tofu/terraform.tfvars
   tofu -chdir=tofu state list

Escribe ``yes`` cuando ``tofu destroy`` pida confirmación. Si reutilizaste una clave existente mediante ``ssh_key_id``, ``tofu destroy`` eliminará únicamente el servidor y conservará intacta tu llave SSH en Cherry Servers para futuros Cómos. La salida de ``tofu -chdir=tofu state list`` debe quedar completamente vacía.

.. warning::
   **No olvides destruir tus instancias manuales:** ``tofu destroy`` elimina únicamente los recursos creados por OpenTofu en la Sección 3. Entra al **Portal de Cherry Servers** y destruye también el servidor objetivo que creaste manualmente en la **Sección 1E**, así como el servidor de control en la nube si optaste por rentar uno en la **Sección 1A**, para evitar cargos residuales en tu cuenta.

5. Retos de Aprendizaje y Práctica
==================================

Pon a prueba tu criterio operativo con estos cuatro desafíos prácticos sin soluciones prefabricadas:

#. **Reto 1: Migración a Inventario YAML en** ``inventory.yaml``

   * El formato INI es compacto, pero limitado para jerarquías complejas. Convierte ``inventory.ini`` a la sintaxis estructurada oficial de YAML en ``inventory.yaml`` usando ``all.children.webservers.hosts`` y verifica la conectividad con ``ansible -i inventory.yaml -m ansible.builtin.ping webservers``.

#. **Reto 2: Generación Automática del Inventario desde OpenTofu**

   * En lugar de actualizar la IP con ``sed`` tras ``tofu apply``, investiga cómo usar el recurso ``local_file`` de OpenTofu junto con ``templatefile()`` para generar automáticamente ``inventory.ini`` con la IP pública del servidor aprovisionado.

#. **Reto 3: Inventario Dinámico con la API de Cherry Servers y** ``inventory.py``

   * En entornos elásticos las direcciones IP cambian con frecuencia. Ansible admite **inventarios dinámicos** mediante cualquier script ejecutable con ``chmod +x`` que al recibir ``--list`` imprima un JSON válido de grupos y hosts. Escribe un script en Python que consulte el punto de acceso ``GET https://api.cherryservers.com/v1/projects/{project_id}/servers`` usando tu token de API y pruébalo con ``ansible-playbook -i inventory.py playbook.yaml``.

#. **Reto 4: Persistencia de Políticas SELinux con** ``semanage fcontext``

   * En este laboratorio aplicaste el contexto directamente en los inodos mediante ``setype`` en los módulos ``ansible.builtin.file`` y ``ansible.builtin.template``. Sin embargo, ejecutar ``restorecon -Rv /srv/webapp`` restauraría el tipo base ``var_t``. Investiga cómo instalar ``policycoreutils-python-utils`` y usar ``community.general.sefcontext`` para persistir la regla ``/srv/webapp(/.*)? -> httpd_sys_content_t`` en la base de datos de SELinux, verificando que ``restorecon`` conserve la etiqueta correcta.

Referencias Oficiales
=====================

* `CentOS Stream: propósito y modelo de entrega continua <https://www.centos.org/centos-stream/>`__
* `Documentación oficial de Ansible <https://docs.ansible.com/ansible/latest/>`__
* `Colección ansible.posix en Ansible Docs <https://docs.ansible.com/ansible/latest/collections/ansible/posix/>`__
* `Colección ansible.builtin en Ansible Docs <https://docs.ansible.com/ansible/latest/collections/ansible/builtin/>`__
* `Guía oficial de uso de SELinux en RHEL 10 <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/secure-getting_started_with_selinux>`__
* `Documentación oficial de Firewalld <https://firewalld.org/documentation/>`__
* `Documentación oficial de OpenTofu <https://opentofu.org/docs/>`__

Dudas y Preguntas
-----------------

Si tienes alguna pregunta, encuentras un detalle técnico o quieres compartir cómo resolviste los retos, abre una conversación en nuestro repositorio oficial:

* `Reportar una incidencia o consulta en GitLab <https://gitlab.com/renich/cherry-servers/-/issues>`__
* Siguiente laboratorio de la serie: `Cómo 04: Primitivas de Infraestructura DNS, NTP y NFSv4 en CentOS Stream 10 <../04-primitives-dns-ntp-nfs/README.rst>`__

Licencia
========

Este documento y todo el material educativo de este Cómo se distribuyen bajo los términos de la **Licencia de Documentación Libre de GNU**, `GFDL versión 1.3 o posterior <../LICENSE>`__. Puedes copiarlo, distribuirlo y modificarlo bajo las condiciones de dicha licencia.
