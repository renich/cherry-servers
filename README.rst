=============================================================================
Serie de «Cómos» Cherry Servers: Infraestructura Empresarial en Linux con IaC
=============================================================================

.. note::
   Serie educativa y práctica de **«Cómos»** diseñada para la **comunidad de software
   libre de Latinoamérica y de habla hispana**, promovida a través de ``r/LinuxEnEspanol``,
   el Fediverso y canales comunitarios sobre la infraestructura en la nube de Cherry Servers.

Visión General
--------------

Este repositorio contiene el código fuente completo, manifiestos declarativos de OpenTofu,
scripts de automatización y guías paso a paso para una serie de **10 Cómos prácticos**
de infraestructura empresarial y administración de sistemas en Linux.

La serie guía a administradores de sistemas, ingenieros de operaciones, desarrolladores
y entusiastas desde los fundamentos de Infraestructura como Código con **OpenTofu**
hasta el despliegue de clústeres de Kubernetes con K3s e infraestructura de cómputo en la nube,
estandarizando sobre **CentOS Stream 10** con **SELinux en modo Enforcing** y cumplimiento
estricto del estándar **FHS 3.0** bajo ``/srv`` o ``/var/lib``.

Principios Fundamentales
------------------------

* **Pedagogía «Manual Primero, Automatización Después»**: Cada Cómo enseña primero la
  anatomía interna del sistema ejecutando los pasos manualmente por SSH, para luego consolidar
  todo en un script declarativo ``bootstrap.bash`` o receta reproducible en segundos.
* **Control Estricto de Costos y Dimensionamiento Justo**: Cada Cómo está diseñado para costar
  centavos por hora. La ejecución completa de los 10 Cómos consume aproximadamente
  **~$2.50 USD en total**, permitiendo experimentar con arquitecturas empresariales con un
  presupuesto mínimo.
* **Infraestructura Declarativa y FOSS**: Manifiestos de OpenTofu planos, lineales y 100% abiertos.
* **Seguridad Criptográfica Estricta**: Acceso remoto exclusivamente mediante llaves **Ed25519**
  con ``PermitRootLogin prohibit-password``, cero acceso por contraseña a ``root``.
* **Estándares GNU/POSIX y FHS 3.0**: Sintaxis canónica de utilidades de línea de comandos,
  cuentas dedicadas de sistema con ``/sbin/nologin`` y sandboxing de servicios en Systemd
  mediante ``ProtectHome=true`` y ``ProtectSystem=full``.
* **Postura Empresarial con SELinux**: Operación continua bajo modo Enforcing mediante
  etiquetado correcto de contextos con ``restorecon``, sin desactivar la seguridad.
* **Disciplina de Destrucción**: Flujo obligatorio de ``tofu destroy`` al final de cada
  Cómo para cultivar una gestión responsable de recursos en la nube.

Crédito Promocional para la Comunidad de $20 USD
------------------------------------------------

Para que los estudiantes, administradores de sistemas y entusiastas puedan realizar las prácticas de esta serie en servidores reales sin costo personal, gestionamos con el equipo de **Cherry Servers** un patrocinio directo para la comunidad:

* **Enlace oficial de registro:** `Portal de bienvenida Cherry Servers <https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol>`__
* **Código de promoción:** ``LinuxEnEspanol``
* **Beneficio:** **$20 USD** de saldo de regalo para desplegar instancias en la nube; se acreditan unas horas tras validar tu cuenta.
* **Cobertura:** Con este saldo cubres con holgura los 10 laboratorios de la serie, cuyo costo acumulado estimado es de apenas ~$2.50 USD, siempre que apliques la regla de oro de destruir los recursos con ``tofu destroy`` al terminar cada práctica.

Matriz de Cómos y Presupuesto
-----------------------------

.. list-table:: Planificación de laboratorios y presupuesto estimado
   :header-rows: 1
   :widths: 4 24 22 12 18 12 10 10

   * - Núm.
     - Cómo
     - Directorio
     - Estado
     - Tipo de Servidor
     - Costo/Hora
     - Tiempo
     - Costo
   * - 01
     - Servidor Luanti Voxel FOSS
     - `01-luanti-tofu <01-luanti-tofu/>`__
     - Publicado
     - Cloud VPS 2, 2 vCPU y 2 GB RAM
     - ~$0.033 EUR/hr
     - 1.0 hrs
     - **$0.03 USD**
   * - 02
     - Caddy y Vaultwarden en Podman
     - `02-caddy-podman <02-caddy-podman/>`__
     - Publicado
     - Small VPS, 1 vCPU y 1 GB RAM
     - ~$0.015 EUR/hr
     - 2.0 hrs
     - **$0.03 USD**
   * - 03
     - Automatización con Ansible
     - `03-ansible <03-ansible/>`__
     - Publicado
     - Small VPS, 1 vCPU y 1 GB RAM
     - ~$0.015 EUR/hr
     - 1.0 hrs
     - **$0.02 USD**
   * - 04
     - Primitivas DNS, NTP y NFSv4.2
     - `04-primitives-dns-ntp-nfs <04-primitives-dns-ntp-nfs/>`__
     - Publicado
     - 2x Cloud VPS 1, 1 vCPU y 1 GB RAM
     - ~$0.030 EUR/hr
     - 2.0 hrs
     - **$0.06 USD**
   * - 05
     - Almacenamiento S3 con Garage
     - ``05-garage-s3``
     - Próximamente
     - 3x Small/Spot VMs
     - ~$0.045 EUR/hr
     - 3.0 hrs
     - **$0.14 USD**
   * - 06
     - Clúster K3s Mononodo
     - ``06-k3s-single``
     - Próximamente
     - Small VPS, 2 vCPU y 4 GB RAM
     - ~$0.033 EUR/hr
     - 2.0 hrs
     - **$0.07 USD**
   * - 07
     - Clúster K3s Multinodo
     - ``07-k3s-cluster``
     - Próximamente
     - 3x Small VPS, 2 vCPU y 2 GB RAM
     - ~$0.045 EUR/hr
     - 3.0 hrs
     - **$0.14 USD**
   * - 08
     - Inferencia IA Gemma 4 en CPU
     - ``08-baremetal-gemma-ai``
     - Próximamente
     - Spot Bare Metal E5-1650V3
     - ~$0.115 EUR/hr
     - 3.0 hrs
     - **$0.35 USD**
   * - 09
     - Topología de Red OpenStack
     - ``09-openstack-topo``
     - Próximamente
     - 3x Spot Bare Metal E5-1620
     - ~$0.276 EUR/hr
     - 2.0 hrs
     - **$0.55 USD**
   * - 10
     - OpenStack con Kolla-Ansible
     - ``10-openstack-kolla``
     - Próximamente
     - 3x Spot Bare Metal E5-1620
     - ~$0.276 EUR/hr
     - 4.0 hrs
     - **$1.10 USD**
   * - Total
     - Serie Completa
     - 10 Cómos
     - 4 publicados
     - Toda la serie
     - Variable
     - ~23 hrs
     - **~$2.50 USD**

Estructura del Repositorio
--------------------------

.. code-block:: text

   ~/Projects/cherry-servers/
   ├── GNUmakefile                        # Puerta de calidad local: linters, formatos, OpenTofu e higiene
   ├── CHANGELOG.rst                      # Registro de hitos de la serie en formato Keep a Changelog 1.1.0
   ├── LICENSE                            # Licencia GNU FDL v1.3+ para la documentación
   ├── README.rst                         # Documentación maestra del repositorio en reStructuredText
   └── 01-luanti-tofu/ ... 10-openstack-kolla/
       ├── README.rst                     # Guía completa del Cómo en reStructuredText
       ├── assets/
       │   ├── hero.png                   # Banner gráfico técnico 16:9 para Reddit
       │   └── telegram-banner.png        # Banner gráfico 16:9 optimizado para Telegram
       ├── tofu/                          # Manifiestos planos de OpenTofu sin módulos anidados
       │   ├── provider.tf
       │   ├── main.tf
       │   ├── variables.tf
       │   ├── outputs.tf
       │   └── terraform.tfvars.example
       └── scripts/                       # Scripts declarativos de arranque con extensión .bash

Estándares de Documentación y Verificación
------------------------------------------

* **Justificación de reStructuredText:** Este proyecto es 100% libre y de código abierto. La documentación oficial del Kernel de Linux estandariza sobre reStructuredText con Sphinx; si es el estándar del Kernel de Linux, es el estándar para toda la documentación pública del repositorio.
* **Uniformidad en** ``.rst`` **:** Tanto la documentación raíz como `CHANGELOG.rst <CHANGELOG.rst>`__ y cada guía ``README.rst`` dentro de los Cómos se redactan íntegramente en reStructuredText con sangría de 3 espacios en directivas.
* **Puerta de calidad automatizada:** Ejecuta ``make check`` en la raíz del repositorio para validar formato de OpenTofu, sintaxis ``tofu validate``, reglas de ``crstlint`` y ``rstcheck``, ``shellcheck`` en scripts ``.bash``, ``ansible-lint``, higiene de enlaces/activos y estado limpio sin recursos activos en ``terraform.tfstate``.

Licencia
--------

Copyright © 2026 Rénich Bon Ćirić ``<renich@evalinux.com>``

Se concede permiso para copiar, distribuir y/o modificar este documento y los Cómos de esta serie bajo los términos de la **Licencia de Documentación Libre de GNU**, Versión 1.3 o cualquier versión posterior publicada por la Free Software Foundation; sin Secciones Invariantes, sin Textos de Portada y sin Textos de Contraportada.

.. code-block:: text

   SPDX-License-Identifier: GFDL-1.3-or-later

Los ejemplos de código, scripts en Bash y manifiestos de Infraestructura como Código en OpenTofu contenidos en este repositorio se licencian en paralelo bajo la **GNU General Public License v3.0 o posterior**, ``GPL-3.0-or-later``, para permitir su libre reutilización e integración técnica.

Una copia completa de la licencia se encuentra en el archivo `LICENSE`_ en la raíz del repositorio.

.. _LICENSE: LICENSE
