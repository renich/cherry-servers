# Cómo automatizar y reconstruir servidores con Ansible en CentOS Stream 10

> **Cómo 03 — Automatización y Reconstrucción con Ansible**
>
> * **Versión:** `v1.0.0`
> * **Fecha:** `2026-10-02`
> * **Rama de Git:** [`03-ansible`](https://gitlab.com/renich/cherry-servers/-/tree/03-ansible)
> * **Licencia:** [`GFDL-1.3-or-later`](../LICENSE)
> * **Tipo de instancia:** Cloud VPS 1 (Gen 2: 1 vCore/1 GB RAM/20GB SSD)
> * **Costo por hora:** ~$0.015 EUR/hora (~$0.017 USD/hora)
> * **Tiempo promedio:** 1 hora
> * **Gasto estimado total:** ~$0.02 USD

---

¡Hola! 👋

Te doy una cordial bienvenida a este **tercer Cómo** de nuestra serie práctica de infraestructura y administración de sistemas en Linux para la comunidad de software libre de Latinoamérica y el mundo.

En los dos Cómos anteriores aprendiste los fundamentos de administración a bajo nivel: cómo instalar paquetes RPM, estructurar directorios bajo el estándar **FHS 3.0**, gestionar servicios con **Systemd**, orquestar contenedores con **Podman Quadlets** y gobernar la seguridad con **SELinux en modo Enforcing**.

Sin embargo, configurar servidores ejecutando comandos manualmente por SSH uno por uno no escala en entornos de producción. Si tu servidor sufre una falla de hardware o necesitas replicar exactamente el mismo servicio en cinco máquinas distintas, el trabajo manual introduce errores humanos, inconsistencias y pérdida de tiempo.

Aquí es donde entra **Ansible**: una herramienta de automatización y gestión de configuraciones **sin agentes** (*agentless*) que opera de forma declarativa e **idempotente** a través de SSH estándar.

Siguiendo nuestra filosofía pedagógica **«Manual Primero, Automatización Después»**, en este laboratorio primero comprenderás cómo opera Ansible desde la línea de comandos de tu estación de trabajo local, construirás un Playbook declarativo paso a paso, comprobarás el principio de idempotencia y desvío de configuración (*configuration drift*), y finalmente orquestarás el aprovisionamiento de la máquina virtual con **OpenTofu**.

---

## 1. Prerrequisitos del Laboratorio

1. Un servidor en la nube con **CentOS Stream 10** (o máquina virtual local) con acceso SSH como `root` mediante clave pública criptográfica Ed25519 (`~/.ssh/id_ed25519.pub`).
   * **Saldo promocional patrocinado ($20 USD):** Puedes desplegar este laboratorio y toda la serie sin costo gracias al patrocinio de **Cherry Servers**. Regístrate mediante [este enlace de bienvenida](https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol) utilizando el código promocional `LinuxEnEspanol` para recibir **$20 USD de crédito de regalo**.
   * Si aún no cuentas con una clave Ed25519 en tu estación de trabajo:

     ```bash
     ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"
     ```

1. Clientes/herramientas locales instaladas en tu estación de trabajo (**Fedora Linux**):

   ```bash
   sudo dnf -y install ansible-core ansible-collection-ansible-posix opentofu curl jq openssh-clients
   ```

   > **Disponibilidad del paquete RPM:** El paquete `ansible-collection-ansible-posix` está disponible oficialmente tanto en **Fedora Linux** como en **EPEL 10** para CentOS Stream 10 (`ansible-collection-ansible-posix-2.2.1`). Puedes instalarlo directamente con DNF en tu estación de trabajo.

1. Gestión declarativa de colecciones con Ansible Galaxy (`requirements.yaml`):

   Aunque Fedora y EPEL 10 empaquetan esta colección como RPM del sistema, en la administración profesional de infraestructura la mejor práctica es no acoplar tus playbooks al gestor de paquetes del host. Declarar las dependencias en un archivo `requirements.yaml` permite que tu proyecto sea portátil y reproducible en cualquier estación de trabajo o pipeline de CI/CD (independientemente de si corre en Fedora, Debian, Ubuntu o macOS):

   ```bash
   cat << 'EOF' > requirements.yaml
   ---
   collections:
     - name: ansible.posix
       version: ">=1.5.0"
   EOF
   ```

   Instala las colecciones declaradas en tu entorno local con `ansible-galaxy`:

   ```bash
   ansible-galaxy collection install -r requirements.yaml
   ```

---

### Postura de Privilegios: Acceso Directo como Root Frente a Sudo

En la administración moderna de infraestructura en la nube existe una distinción crucial entre tu estación de trabajo personal y un servidor remoto automatizado:

1. **En tu estación de trabajo (Fedora Linux):** Operas como un usuario mortal sin privilegios. Utilizas `sudo` estrictamente cuando modificas paquetes o servicios del sistema local (`sudo dnf -y install ...`) para evitar accidentes en tu entorno de trabajo diario.
1. **En servidores remotos en la nube:** El acceso por contraseña está estrictamente deshabilitado (`PermitRootLogin prohibit-password`). Solo quien posea tu clave criptográfica privada Ed25519 puede abrir una sesión. Crear un usuario intermedio (por ejemplo, `ansible` o `admin`) simplemente para otorgarle privilegios universales sin contraseña en `/etc/sudoers` (`NOPASSWD: ALL`) no aporta seguridad real: es **simulación de seguridad** (*security theater*) que añade consumo de recursos, ruido en los registros del sistema y complejidad innecesaria.
1. **Verdadero principio de menor privilegio:** En lugar de complicar el transporte de administración, la seguridad real se implementa en los servicios: cada aplicación se ejecuta bajo una cuenta de sistema dedicada sin shell interactiva (`/sbin/nologin`), con permisos estrictos de directorios bajo **FHS 3.0** y confinamiento por **SELinux**. La cuenta `root` es utilizada exclusivamente por el motor de orquestación para construir y vigilar esas fronteras.

---

## 2. Construcción y Configuración Manual vía SSH y Ansible CLI (El Núcleo del Aprendizaje)

### Paso A: Fundamentos de Ansible y Arquitectura sin Agentes

A diferencia de otras soluciones tradicionales de orquestación (como Puppet, Chef o SaltStack), Ansible no requiere que instales ningún demonio o agente en segundo plano en el servidor remoto.

Ansible opera bajo el modelo **Push sobre SSH**:

1. Tu estación de trabajo local lee el inventario y el Playbook.
1. Traduce las tareas declarativas a pequeños módulos independientes en Python.
1. Transfiere y ejecuta los módulos en el nodo remoto a través de una conexión SSH segura.
1. Recibe la respuesta en formato JSON estructurado y remueve los archivos temporales.

Para que esto funcione, el único requisito en el servidor gestionado es contar con **Python 3** (que ya viene preinstalado por defecto en la imagen oficial de CentOS Stream 10).

Verifícalo conectándote una única vez por SSH a tu servidor:

```bash
ssh root@<IP_DEL_SERVIDOR>
```

Dentro del servidor, comprueba la versión del intérprete:

```bash
python3 --version
```

Verás una salida similar a `Python 3.12.x` (o superior). Sal de la sesión remota para regresar a tu terminal local:

```bash
exit
```

A partir de este momento, **todas las operaciones se ejecutan desde tu estación de trabajo local**.

---

### Paso B: Configuración del Entorno Local y Verificación Estricta de Huellas SSH

En tu máquina local, ubícate en el directorio de trabajo del laboratorio y crea el archivo de configuración `ansible.cfg`:

```bash
cat << 'EOF' > ansible.cfg
[defaults]
inventory = inventory.ini
remote_user = root
host_key_checking = True
retry_files_enabled = False
interpreter_python = auto_silent
stdout_callback = yaml

[privilege_escalation]
become = False
EOF
```

#### Parámetros clave de `ansible.cfg`

* `inventory = inventory.ini`: Establece el archivo de inventario predeterminado para no tener que especificar `-i inventory.ini` en cada comando.
* `remote_user = root`: Define la cuenta remota para la sesión SSH. Al operar directamente con la clave Ed25519 de `root`, no utilizamos `sudo` innecesario en el servidor remoto.
* `host_key_checking = True`: **Seguridad criptográfica estricta.** Mantiene activa la verificación de huellas en `~/.ssh/known_hosts`. Desactivar esta directiva en tutoriales es una mala práctica común que vuelve vulnerable la conexión ante ataques de intermediario (*Man-in-the-Middle* o MITM).
* `interpreter_python = auto_silent`: Detecta automáticamente la ruta óptima de Python en el servidor remoto sin emitir advertencias molestas.
* `stdout_callback = yaml`: Formatea la salida de Ansible en la terminal en YAML legible en lugar del JSON compacto por defecto.

#### Mantenimiento de `known_hosts` con `ssh-keyscan` y `ssh-keygen`

Al mantener `host_key_checking = True`, tu cliente SSH verificará la identidad del servidor remoto antes de transmitir cualquier dato.

Si bien en el Paso A aceptaste interactivamente la huella en tu terminal al conectar manualmente, en automatizaciones, pipelines y despliegues desatendidos el patrón estándar de la industria es registrar previamente la clave pública con la herramienta estándar `ssh-keyscan` para evitar interrupciones por prompts interactivos:

```bash
ssh-keyscan -t ed25519 <IP_DEL_SERVIDOR> >> ~/.ssh/known_hosts
```

> **Consejo de Sysadmin:** En entornos de nube donde creas y destruyes servidores dinámicamente, es común que una IP reciclada tenga una clave de host anterior guardada. Si alguna vez recibes una advertencia de colisión de clave (`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`), no desactives la seguridad; simplemente purga la entrada obsoleta con el comando estándar:
>
> ```bash
> ssh-keygen -R <IP_DEL_SERVIDOR>
> ```
>
> Y vuelve a ejecutar `ssh-keyscan` para registrar la identidad del nuevo nodo.

Ahora crea el archivo de inventario `inventory.ini`. Sustituye `<IP_DEL_SERVIDOR>` por la dirección IP pública real de tu nodo CentOS Stream 10:

```bash
cat << 'EOF' > inventory.ini
[webservers]
cherry-node ansible_host=<IP_DEL_SERVIDOR> ansible_user=root

[webservers:vars]
ansible_python_interpreter=/usr/bin/python3
EOF
```

---

### Paso C: Comprobación de Conectividad y Módulos Ad-Hoc

Ansible permite ejecutar comandos puntuales denominados **ad-hoc** sin necesidad de escribir un Playbook completo.

Prueba la conectividad utilizando el nombre completo de colección (**FQCN**) `ansible.builtin.ping`:

```bash
ansible -m ansible.builtin.ping webservers
```

> **Aclaración importante:** El módulo `ping` de Ansible **no envía paquetes ICMP de red**. Ejecuta un micro-script en Python en el nodo remoto para comprobar la autenticación SSH, la integridad del canal y la capacidad de ejecutar código en Python.

La respuesta exitosa se verá así:

```yaml
cherry-node | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Ahora inspecciona la recolección automática de variables del sistema (*facts*) mediante el módulo `ansible.builtin.setup`:

```bash
ansible -a "filter=ansible_distribution*" -m ansible.builtin.setup webservers
```

Ansible te reportará los hechos descubiertos del sistema operativo en tiempo real:

```yaml
cherry-node | SUCCESS => {
    "ansible_facts": {
        "ansible_distribution": "CentOS Stream",
        "ansible_distribution_major_version": "10",
        "ansible_distribution_version": "10"
    },
    "changed": false
}
```

---

#### El Manual de Componentes y Módulos: `ansible-doc`

Antes de escribir una sola línea de código en tu Playbook, necesitas saber cómo explorar la documentación de Ansible. No necesitas memorizar parámetros ni buscar recetas dispersas en internet: Ansible incluye su propio sistema de manual integrado directamente en tu terminal:

* **Consultar el manual completo de un módulo:**

  ```bash
  ansible-doc ansible.posix.selinux
  ```

  Despliega una interfaz interactiva (análoga a las páginas `man`) con la descripción del módulo, requisitos del sistema, parámetros disponibles, valores por defecto y ejemplos de uso prácticos.

* **Obtener un snippet conciso listo para usar (`-s`):**

  ```bash
  ansible-doc -s ansible.posix.selinux
  ansible-doc -s ansible.posix.firewalld
  ansible-doc -s ansible.builtin.dnf
  ```

  La bandera `-s` (*snippet*) imprime la estructura YAML exacta del módulo con los tipos de datos esperados y marcas de campos obligatorios (`# (required)`), ideal para consultar rápidamente la sintaxis mientras construyes tu receta.

* **Documentación oficial upstream en la web:**
   * Colección [`ansible.posix`](https://docs.ansible.com/ansible/latest/collections/ansible/posix/): Módulos para cortafuegos (`firewalld`), políticas de seguridad (`selinux`), variables del kernel (`sysctl`) y montajes.
   * Colección [`ansible.builtin`](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/): Módulos esenciales del núcleo (`dnf`, `systemd_service`, `file`, `template`, `copy`, `user`, `group`).

---

### Paso D: Creación del Playbook Declarativo e Idempotente (`playbook.yaml`)

Un **Playbook** es un archivo YAML donde describes el **estado deseado** de tu infraestructura. En lugar de ordenar secuencias de comandos imperativos («ejecuta esto, luego esto otro»), defines declaraciones de estado («este paquete debe estar presente», «este servicio debe estar activo», «este archivo debe tener estos permisos»).

Para este laboratorio, automatizarás el despliegue de un servicio web bajo el estándar **FHS 3.0** en `/srv/webapp`, con Nginx, sincronización de hora con Chrony, reglas en Firewalld y políticas de **SELinux en modo Enforcing**.

Primero, crea el directorio para las plantillas Jinja2:

```bash
mkdir -p templates
```

Crea la plantilla para la configuración de Nginx en `templates/webapp.conf.j2`:

```bash
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
```

Crea la plantilla HTML en `templates/index.html.j2`. Observa que utilizamos variables estáticas del host (como la distribución y la dirección IPv4 descubierta) para que la página sea informativa sin alterar la suma de verificación del archivo en corridas subsecuentes:

```bash
cat << 'EOF' > templates/index.html.j2
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Servidor Automatizado con Ansible — Cómo 03</title>
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
        <div class="status-badge">● Sistema Idempotente y Convergente</div>
        <h1>Servidor Desplegado con Ansible</h1>
        <p class="subtitle">
            Este nodo fue configurado y asegurado de forma totalmente declarativa mediante Ansible en
            <strong>CentOS Stream 10</strong> sobre infraestructura de <strong>Cherry Servers</strong>.
        </p>

        <div class="grid">
            <div class="item">
                <div class="label">Nombre de Host</div>
                <div class="value">{{ ansible_hostname }}</div>
            </div>
            <div class="item">
                <div class="label">Distribución</div>
                <div class="value">{{ ansible_distribution }} {{ ansible_distribution_version }}</div>
            </div>
            <div class="item">
                <div class="label">Kernel</div>
                <div class="value">{{ ansible_kernel }}</div>
            </div>
            <div class="item">
                <div class="label">Arquitectura y CPUs</div>
                <div class="value">{{ ansible_architecture }} ({{ ansible_processor_vcpus }} vCPUs)</div>
            </div>
            <div class="item">
                <div class="label">Memoria Total</div>
                <div class="value">{{ ansible_memtotal_mb }} MB</div>
            </div>
            <div class="item">
                <div class="label">Dirección IPv4</div>
                <div class="value">{{ ansible_default_ipv4.address }}</div>
            </div>
        </div>

        <div class="footer">
            Cómo 03 — Serie Educativa de Infraestructura en Linux &bull;
            <a href="https://gitlab.com/renich/cherry-servers" target="_blank" rel="noopener">Repositorio en GitLab</a>
        </div>
    </div>
</body>
</html>
EOF
```

---

### Anatomía y Construcción del Playbook Bloque a Bloque

En lugar de copiar ciegamente un archivo monolítico, analiza la anatomía del Playbook dividida en sus seis bloques arquitectónicos:

#### Bloque 1: Cabecera del Play y Variables Globales (`vars`)

Todo Playbook inicia declarando el grupo objetivo (`hosts: webservers`), activando la recolección de hechos del sistema (`gather_facts: true`) y aislando los parámetros de configuración en variables para no tener valores fijos (*hardcode*) dispersos:

```yaml
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
      - jq
```

#### Bloque 2: Paquetes del Sistema y Sincronización de Tiempo (Chrony)

Instalamos la lista de paquetes en una sola transacción DNF. En Ansible, pasar una lista de paquetes a `name:` es infinitamente más eficiente que usar un bucle `loop:`, ya que DNF resuelve todas las dependencias en una sola ejecución:

```yaml
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
```

#### Bloque 3: Usuario de Sistema y Jerarquía FHS 3.0

Creamos una cuenta de sistema dedicada para aislar los procesos web (`webapp`) sin shell interactiva (`/sbin/nologin`). Observa el manejo de permisos:

1. `useradd -m` crea `/srv/webapp` con permisos restrictivos `0700` por defecto en Linux.
1. Si no modificamos el directorio base, ningún otro usuario podrá acceder a sus subdirectorios.
1. Declaramos explícitamente `/srv/webapp` con permisos `0750` y tipo SELinux `httpd_sys_content_t` para permitir que Nginx atraviese la jerarquía:

```yaml
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
```

#### Bloque 4: Despliegue de Plantillas y Configuración de Nginx

Desplegamos el HTML dinámico y el archivo de configuración en `/etc/nginx/conf.d/webapp.conf`. Notificamos al manejador para que Nginx solo se recargue si el archivo cambió, validamos la sintaxis con `/usr/sbin/nginx -t` y agregamos a `nginx` al grupo secundario `webapp`:

```yaml
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

    - name: Agregar usuario nginx al grupo complementario de webapp para traversal de directorios
      ansible.builtin.user:
        name: nginx
        groups: "{{ webapp_service_group }}"
        append: true
      notify: Recargar servicio Nginx
```

#### Bloque 5: Políticas de Seguridad (SELinux y Firewalld)

Garantizamos que SELinux opere en modo **Enforcing** (cero compromisos de seguridad), habilitamos el cortafuegos con el servicio `http` permanente e inmediato, y aseguramos el arranque del demonio Nginx:

```yaml
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
```

#### Bloque 6: Manejadores de Estado (`handlers`)

Los manejadores solo se ejecutan cuando una tarea emite una notificación (`notify`), evitando recargas innecesarias cuando el sistema ya se encuentra en el estado deseado:

```yaml
  handlers:
    - name: Recargar servicio Nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
```

---

### Consolidación y Verificación del Archivo `playbook.yaml`

Abre tu editor de texto favorito en la terminal (`nano playbook.yaml`, `micro playbook.yaml` o `vim playbook.yaml`) y consolida los bloques en tu archivo final, o utiliza el siguiente comando de referencia asegurando la indentación exacta de dos espacios:

```bash
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
      - jq

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

    - name: Agregar usuario nginx al grupo complementario de webapp para traversal de directorios
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
```

> **Nota Técnica sobre SELinux (`setype` vs `semanage fcontext`):**
> En este Playbook utilizamos `setype: httpd_sys_content_t` en los módulos `file` y `template`. Esto aplica el contexto directamente sobre el inodo en los atributos extendidos del sistema de archivos (`xattr`), de forma idéntica a ejecutar `chcon`. Es una solución ligera que no requiere instalar herramientas adicionales de políticas en el nodo gestionado. En entornos corporativos donde se ejecuten limpiezas rutinarias con `restorecon`, la política base de SELinux en `/srv` devolvería los archivos a `var_t`. En el Reto 4 explorarás cómo persistir reglas permanentes en la base de datos de SELinux con `semanage fcontext` o el módulo `community.general.sefcontext`.

Verifica la sintaxis del Playbook sin ejecutarlo:

```bash
ansible-playbook --syntax-check playbook.yaml
```

Si la sintaxis es correcta, el comando confirmará: `playbook: playbook.yaml`.

---

### Paso E: Ejecución del Playbook y Prueba de Idempotencia

Ejecuta el Playbook por primera vez:

```bash
ansible-playbook playbook.yaml
```

Verás cómo Ansible ejecuta cada tarea en orden. Al finalizar, presentará el resumen de ejecución (*PLAY RECAP*):

```text
PLAY RECAP *********************************************************************
cherry-node   : ok=16   changed=13   unreachable=0    failed=0    skipped=0
```

Observa que `changed=13`: Ansible detectó que los paquetes no estaban instalados, los usuarios y directorios no existían y los archivos faltaban, por lo que aplicó los cambios necesarios para alcanzar el estado deseado.

Ahora realiza la prueba de verificación HTTP desde tu estación de trabajo:

```bash
curl -s http://<IP_DEL_SERVIDOR> | grep "Servidor Desplegado con Ansible"
```

Verás la línea correspondiente confirmando que Nginx está sirviendo el contenido con permisos y contexto SELinux correctos.

#### La Prueba de Fuego: Idempotencia Absoluta

Vuelve a ejecutar exactamente el mismo comando:

```bash
ansible-playbook playbook.yaml
```

Observa atentamente el resultado del resumen:

```text
PLAY RECAP *********************************************************************
cherry-node   : ok=15   changed=0    unreachable=0    failed=0    skipped=0
```

**`changed=0`**. Esto demuestra el principio fundamental de la **idempotencia**: el sistema ya se encuentra exactamente en el estado deseado, por lo que Ansible no modifica nada, no reinicia servicios innecesariamente y no altera el sistema operativo.

---

### Paso F: Reconstrucción y Recuperación ante Desvío (*Configuration Drift*)

El desvío de configuración (*drift*) ocurre cuando alguien modifica un archivo a mano por SSH, detiene un servicio accidentalmente o una actualización rompe un ajuste.

Provoca un desvío deliberado conectándote al servidor y alterando el estado:

```bash
# Conéctate y altera la configuración intencionalmente
ssh root@<IP_DEL_SERVIDOR> "systemctl stop nginx && rm -f /etc/nginx/conf.d/webapp.conf"
```

Si consultas el servicio web ahora con `curl http://<IP_DEL_SERVIDOR>`, fallará con un error de conexión rechazada.

En un esquema de administración tradicional, tendrías que recordar qué se borró o qué comando faltó ejecutar. Con Ansible, simplemente ejecutas de nuevo tu Playbook:

```bash
ansible-playbook playbook.yaml
```

Ansible detectará automáticamente que el archivo `/etc/nginx/conf.d/webapp.conf` falta y que el servicio `nginx` está detenido. Restaurará el archivo con su contexto SELinux correspondiente, reactivará el servicio y devolverá el servidor al 100% de operatividad:

```text
PLAY RECAP *********************************************************************
cherry-node   : ok=16   changed=2    unreachable=0    failed=0    skipped=0
```

Vuelve a probar con `curl`:

```bash
curl -I http://<IP_DEL_SERVIDOR>
```

El servidor responderá con `HTTP/1.1 200 OK`.

---

## 3. Automatización Declarativa con OpenTofu (Infraestructura como Código)

Hasta este punto has configurado el sistema operativo utilizando un servidor previamente existente. Pero en la ingeniería moderna de infraestructura, el aprovisionamiento de la máquina virtual también se define como código.

**OpenTofu** y **Ansible** forman una combinación perfecta:

* **OpenTofu** aprovisiona el hardware, las redes, los discos y la máquina virtual en la nube.
* **Ansible** orquesta el software, los paquetes, las políticas y los servicios dentro del sistema operativo.

### Manifiestos de OpenTofu en el Repositorio

Ingresa al subdirectorio `tofu/`:

```bash
cd tofu
```

Explora los archivos disponibles:

* `provider.tf`: Declara el proveedor de Cherry Servers (`cherryservers/cherryservers ~> 1.5.3`).
* `variables.tf`: Define los parámetros configurables (ID del proyecto, región, plan del servidor y clave SSH).
* `main.tf`: Registra tu clave pública SSH y crea la máquina virtual con CentOS Stream 10.
* `outputs.tf`: Expone la dirección IP asignada y el comando para ejecutar Ansible.

### Configurar Variables Locales y Desplegar (`tofu apply`)

Copia el archivo de variables de ejemplo:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tus credenciales reales:

```hcl
cherry_auth_token = "TU_API_TOKEN_AQUI"
project_id        = 123456
region            = "LT-Siauliai"
server_plan       = "B1-1-1gb-20s-shared"
server_image      = "centos_stream_10_64bit"
server_name       = "0.ansible.linenes.tld"
ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... tu_correo@ejemplo.com"
spot_instance     = false
```

Inicializa y valida el entorno:

```bash
tofu init
tofu validate
```

Despliega el servidor en Cherry Servers:

```bash
tofu apply
```

Confirma escribiendo `yes`. En aproximadamente 60 segundos, OpenTofu creará el servidor e imprimirá la salida con la dirección IP pública:

```text
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

ansible_playbook_command = "ansible-playbook -i inventory.ini playbook.yaml"
server_ip = "192.0.2.100"
ssh_command = "ssh root@192.0.2.100"
web_url = "http://192.0.2.100"
```

Regresa al directorio raíz de este Cómo:

```bash
cd ..
```

Registra la huella digital SSH del nuevo servidor para mantener la validación estricta de host keys:

```bash
ssh-keyscan -t ed25519 192.0.2.100 >> ~/.ssh/known_hosts
```

Actualiza la dirección IP en tu archivo `inventory.ini`:

```bash
sed -i 's/ansible_host=[^ ]*/ansible_host=192.0.2.100/' inventory.ini
```

Y ejecuta el Playbook para aprovisionar el servidor completo desde cero:

```bash
ansible-playbook playbook.yaml
```

En menos de un minuto tendrás un servidor completamente nuevo, configurado, endurecido e idéntico al anterior.

---

## 4. Destrucción del Servidor y Control de Costos

Una regla de oro en la administración de sistemas en la nube es la **disciplina de costos**. Cuando termines de realizar tus prácticas y retos, destruye la infraestructura para no acumular cobros:

```bash
cd tofu
tofu destroy
```

Escribe `yes` cuando OpenTofu lo solicite. En unos instantes los recursos se liberarán por completo.

Limpia la huella del servidor en tus claves conocidas para evitar advertencias en futuros laboratorios:

```bash
ssh-keygen -R 192.0.2.100
```

---

## 5. Retos de Aprendizaje y Práctica

Pon a prueba tus habilidades de automatización con estos desafíos prácticos diseñados para profundizar en el ecosistema de Ansible:

1. **Reto 1: Migración a Inventario YAML (`inventory.yaml`)**
   * El formato INI es compacto pero limitado en estructuras complejas. Convierte tu `inventory.ini` a la sintaxis estructurada oficial de YAML (`inventory.yaml`). Define la jerarquía de grupos utilizando `all.children.webservers.hosts` y variables bajo la directiva `vars:`. Verifica que funcione ejecutando `ansible -i inventory.yaml -m ansible.builtin.ping webservers`.
1. **Reto 2: Generación Automática del Inventario desde OpenTofu**
   * En lugar de copiar y pegar la dirección IP manualmente tras ejecutar `tofu apply`, investiga cómo utilizar el recurso `local_file` de OpenTofu junto con la función `templatefile()` para escribir o actualizar automáticamente el archivo `inventory.ini` con la IP pública del servidor aprovisionado.
1. **Reto 3: Inventario Dinámico con la API de Cherry Servers (`inventory.py`)**
   * En entornos elásticos, los servidores cambian de IP continuamente. Ansible soporta **inventarios dinámicos** mediante cualquier script ejecutable (`chmod +x`) que al ejecutarse con la bandera `--list` imprima un JSON con la estructura de hosts. Construye un pequeño script en Python que consulte el endpoint `GET https://api.cherryservers.com/v1/projects/{project_id}/servers` utilizando tu token de autorización y devuelva los nodos activos para consumirlos directamente con `ansible-playbook -i inventory.py playbook.yaml`.
1. **Reto 4: Persistencia de Políticas SELinux con `semanage fcontext`**
   * En este laboratorio aplicamos el contexto directamente en los inodos mediante el módulo `ansible.builtin.file`. Sin embargo, si en el futuro se ejecuta `restorecon -Rv /srv/webapp`, el sistema restaurará los contextos por defecto de la política base (`var_t`). Investiga cómo instalar `policycoreutils-python-utils` y utilizar el módulo `community.general.sefcontext` (o comandos equivalentes) para persistir la regla `/srv/webapp(/.*)? -> httpd_sys_content_t` en la base de datos central de SELinux, asegurando que `restorecon` preserve la etiqueta correcta.

---

### Dudas y Preguntas

Si tienes alguna pregunta, encuentras un detalle técnico o deseas compartir cómo resolviste los retos, abre un reporte o inicia una discusión en nuestro repositorio oficial:

👉 **[Reportar un issue o consulta en GitLab](https://gitlab.com/renich/cherry-servers/-/issues)**

---

## Licencia

Este documento y todo el material educativo de esta serie se distribuyen bajo los términos de la **Licencia de Documentación Libre de GNU** ([GFDL versión 1.3 o posterior](../LICENSE)). Puedes copiarlo, distribuirlo y modificarlo bajo las condiciones de dicha licencia.
