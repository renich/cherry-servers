=========
Changelog
=========

Todos los cambios notables en la serie de «Cómos» sobre Cherry Servers se documentan en este archivo.

El formato está basado en `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__,
y este proyecto utiliza versionado semántico por hitos de la serie siguiendo
`Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__ hasta alcanzar ``v1.0.0`` al completar los 10 Cómos.

[Unreleased]
------------

Compare: `unreleased diff`_.

.. rubric:: Added

* Preparación del alcance técnico para el Cómo 06 de Kubernetes ligero K3s en un nodo.

`[0.5.1]`_ - 2026-11-26
-----------------------

.. rubric:: Added

* Sección ``¿Por qué CentOS Stream 10?`` y **Referencias Oficiales** verificadas con HTTP 200 en ``README.rst`` y en las cinco guías publicadas ``01-luanti-tofu`` hasta ``05-garage-s3``.
* Soporte uniforme de reutilización de llaves SSH existentes mediante ``ssh_key_id`` con validación ``trimspace`` en los manifiestos OpenTofu de los Cómos 01 a 05.
* Objetivo ``verify-templates`` en ``GNUmakefile`` para evaluar empíricamente cada llamada ``templatefile()`` vía ``tofu console`` y comprobar sintaxis ``bash -n`` sobre el script renderizado, junto con detección de marcado RST anidado roto y marcadores angulares en bloques Bash.

.. rubric:: Fixed

* Corrección de fallos de ejecución en ``templatefile()`` dentro de ``02-caddy-podman/scripts/bootstrap.bash``, ``04-primitives-dns-ntp-nfs/scripts/bootstrap.bash`` y ``04-primitives-dns-ntp-nfs/scripts/bootstrap-client.bash``.
* Corrección de contexto SELinux ``httpd_log_t`` sobre ``/var/log/caddy(/.*)?`` y validación sin privilegios ``runuser -u caddy`` en el Cómo 02, alineándolo con CentOS Stream 10 y EPEL 10.
* Corrección en el Cómo 01 para propagar ``var.server_port`` hacia ``/etc/sysconfig/minetest/default.conf``, advertir sobre el rol administrativo de ``name``, ordenar SELinux/Firewalld antes del arranque del servicio y añadir Paso H con guardia ``%ghost`` de DNF5.
* Corrección en el Cómo 03 del directorio aislado de práctica manual, marcado RST anidado, conteo real ``changed=3`` en recuperación de desvío, eliminación de duplicidad de ``ansible.posix`` y captura dinámica de IP desde ``tofu output``.
* Corrección integral en el Cómo 05 de todas las variables de entorno en español con instrucciones explícitas de obtención, Quadlet renderizable por heredoc, lectura binaria real durante la prueba de caos 2 de 3, advertencia sobre exposición pública de buckets web y reemplazo del uso engañoso de ``eval``.
* Documentación explícita en los cinco Cómos sobre dónde obtener cada dirección IP, secreto, ``cherry_auth_token``, ``project_id``, ``ssh_public_key`` y ``ssh_key_id``, así como limpieza de ``known_hosts`` y servidores manuales al finalizar.

`[0.5.0]`_ - 2026-11-24
-----------------------

.. rubric:: Added

* Implementación completa del Cómo 05 en ``05-garage-s3/`` con clúster distribuido **Garage v2.6.0** en tres zonas ``z1``, ``z2`` y ``z3`` sobre Podman Quadlets, aislamiento Firewalld ``internal`` frente a ``public``, FHS 3.0 bajo ``/srv/garage`` y proxy inverso Caddy con Let's Encrypt sobre ``sslip.io``.
* Scripts idempotentes ``05-garage-s3/scripts/bootstrap-node0.bash`` y ``05-garage-s3/scripts/bootstrap-peer.bash`` con convergencia asíncrona en ``garage-cluster-init.service``, generación de credenciales ``0600`` y guardia ``%ghost`` para ``dnf-automatic``.
* Regla persistente de SELinux ``httpd_log_t`` sobre ``/var/log/caddy(/.*)?`` y validación sin privilegios mediante ``runuser -u caddy -- caddy validate`` para operación limpia en modo Enforcing.
* Soporte en ``05-garage-s3/tofu/`` para reutilización segura de llaves SSH existentes en Cherry Servers mediante ``ssh_key_id`` sin riesgo de eliminación en ``tofu destroy``.
* Guía completa en ``05-garage-s3/README.rst`` verificada en vivo con ``rclone`` HTTPS, servidor web estático y prueba de caos 2 de 3, acompañada de banners 16:9 ``hero.png`` y ``telegram-banner.png``.

.. rubric:: Changed

* Actualización de la tabla de serie en ``README.rst`` marcando el Cómo 05 como publicado con 5 módulos activos.

`[0.4.0]`_ - 2026-11-24
-----------------------

.. rubric:: Added

* Implementación completa del Cómo 04 en ``04-primitives-dns-ntp-nfs/`` con DNS BIND 9 autoritativo y recursivo, NTP con Chrony y NFSv4.2 puro bajo FHS 3.0 y SELinux Enforcing.
* Puerta de calidad automatizada en ``GNUmakefile`` cubriendo OpenTofu, reStructuredText, ShellCheck, Ansible Lint, higiene de enlaces/activos y verificación de ``terraform.tfstate`` limpio.
* Registro histórico de versiones en ``CHANGELOG.rst`` adoptando hitos de serie en reStructuredText.
* Banner gráfico faltante ``02-caddy-podman/assets/telegram-banner.png`` en español técnico 16:9.

.. rubric:: Changed

* Estandarización integral de toda la documentación pública del repositorio y guías de los Cómos 01 a 04 a formato reStructuredText ``README.rst``, retirando los ``README.md``.
* Actualización de ``README.rst`` con ``.. list-table::`` alineado a los directorios reales en disco.
* Ajuste de la plantilla HTML del Cómo 03 en ``03-ansible/templates/index.html.j2`` para reemplazar rayas tipográficas por dos puntos.

.. rubric:: Fixed

* Eliminación de enlaces locales rotos hacia rutas absolutas del disco en ``01-luanti-tofu/README.rst`` y ``02-caddy-podman/README.rst``, reemplazándolos por rutas relativas portables.
* Eliminación de referencias a ramas inexistentes en los comandos de clonado de ``01-luanti-tofu/README.rst`` y ``02-caddy-podman/README.rst``.
* Reemplazo de imagen JPEG mal nombrada en ``02-caddy-podman/assets/hero.png`` por codificación PNG genuina de 1376x768 píxeles.
* Incorporación de ``.ansible/`` al archivo ``.gitignore`` para evitar cachés locales sucias.

.. rubric:: Removed

* Directorio sin uso ``common/`` en la raíz del repositorio.
* Archivos heredados ``01-luanti-tofu/README.md``, ``02-caddy-podman/README.md``, ``03-ansible/README.md`` y ``04-primitives-dns-ntp-nfs/README.md`` tras su migración a ``README.rst``.

`[0.3.0]`_ - 2026-10-02
-----------------------

.. rubric:: Added

* Implementación completa del Cómo 03 en ``03-ansible/`` con automatización y recuperación ante desvío de configuración mediante Ansible Core, Nginx, FHS 3.0, SELinux Enforcing, ``requirements.yaml`` y OpenTofu.
* Banners gráficos ``hero.png`` y ``telegram-banner.png`` en español técnico para el Cómo 03.

`[0.2.0]`_ - 2026-09-26
-----------------------

.. rubric:: Added

* Implementación completa del Cómo 02 en ``02-caddy-podman/`` con Caddy desde EPEL 10, Vaultwarden en Podman Quadlet, TLS automático mediante ``sslip.io``, SELinux Enforcing, ``dnf-automatic`` y ``podman-auto-update``.
* Adopción formal de la licencia ``GFDL-1.3-or-later`` para documentación y ``GPL-3.0-or-later`` para código y manifiestos.
* Integración del enlace promocional patrocinado de Cherry Servers con ``LinuxEnEspanol`` por $20 USD.

`[0.1.0]`_ - 2026-09-18
-----------------------

.. rubric:: Added

* Inicialización del repositorio ``cherry-servers`` y documentación maestra en ``README.rst``.
* Implementación completa del Cómo 01 en ``01-luanti-tofu/`` con servidor dedicado de Luanti mediante COPR y OpenTofu sobre CentOS Stream 10.
* Banners gráficos ``hero.png`` y ``telegram-banner.png`` para el Cómo 01.

.. _unreleased diff: https://gitlab.com/renich/cherry-servers/-/compare/v0.5.1...master
.. _[0.5.1]: https://gitlab.com/renich/cherry-servers/-/releases/v0.5.1
.. _[0.5.0]: https://gitlab.com/renich/cherry-servers/-/releases/v0.5.0
.. _[0.4.0]: https://gitlab.com/renich/cherry-servers/-/releases/v0.4.0
.. _[0.3.0]: https://gitlab.com/renich/cherry-servers/-/releases/v0.3.0
.. _[0.2.0]: https://gitlab.com/renich/cherry-servers/-/releases/v0.2.0
.. _[0.1.0]: https://gitlab.com/renich/cherry-servers/-/releases/v0.1.0
