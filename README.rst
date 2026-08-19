=============================================================================
Serie de «Cómos» Cherry Servers: Infraestructura Empresarial en Linux con IaC
=============================================================================

.. note::
   Serie educativa y práctica de **«Cómos»** diseñada para la **comunidad de software
   libre de Latinoamérica y de habla hispana**, promovida a través de `r/LinuxEnEspanol`,
   el Fediverso y canales comunitarios. Patrocinada por Cherry Servers mediante
   $20 USD en créditos de cómputo promocionales para que cualquier persona interesada
   pueda desplegar y experimentar con los 10 Cómos sin costo.

Visión General
--------------

Este repositorio contiene el código fuente completo, manifiestos declarativos de OpenTofu,
scripts de automatización y guías paso a paso para una serie de **10 Cómos prácticos**
de infraestructura empresarial y administración de sistemas en Linux.

La serie guía a administradores de sistemas, ingenieros de operaciones, desarrolladores
y entusiastas desde los fundamentos de Infraestructura como Código (IaC) con **OpenTofu**
hasta el despliegue de clústeres de Kubernetes (K3s) e infraestructura de cómputo en la nube,
estandarizando sobre **CentOS Stream 10** con **SELinux en modo Enforcing** y cumplimiento
estricto del estándar **FHS 3.0** (``/srv`` o ``/var/lib``).

Principios Fundamentales
------------------------

* **Pedagogía «Manual Primero, Automatización Después»**: Cada Cómo enseña primero la
  anatomía interna del sistema ejecutando los pasos manualmente por SSH, para luego consolidar
  todo en un script declarativo (``bootstrap.bash``) reproducible en segundos.
* **Control Estricto de Costos y Dimensionamiento Justo**: Cada Cómo está diseñado para costar
  centavos por hora. La ejecución completa de los 10 Cómos consume aproximadamente
  **~$2.50 USD en total**, dejando más de **$17.50 USD de crédito intacto** para la exploración
  personal del estudiante.
* **Infraestructura Declarativa y FOSS**: Manifiestos de OpenTofu planos, lineales y 100% abiertos.
* **Seguridad Criptográfica Estricta**: Acceso remoto exclusivamente mediante llaves **Ed25519**
  con ``PermitRootLogin prohibit-password`` (cero acceso por contraseña a root).
* **Estándares GNU / POSIX y FHS 3.0**: Sintaxis canónica de utilidades de línea de comandos,
  cuentas dedicadas de sistema (``/sbin/nologin``) y sandboxing de servicios en Systemd
  (``ProtectHome=true``, ``ProtectSystem=full``).
* **Postura Empresarial con SELinux**: Operación continua bajo modo Enforcing mediante
  etiquetado correcto de contextos (``restorecon``), sin desactivar la seguridad.
* **Disciplina de Destrucción**: Flujo obligatorio de ``tofu destroy`` al final de cada
  Cómo para cultivar una gestión responsable de recursos en la nube.

Matriz de Cómos y Presupuesto
-----------------------------

+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| #  | Cómo                           | Rama de Git        | Versión | Tipo de Servidor     | Costo / Hora  | Tiempo Estim. | Costo / Corrida |
+====+================================+====================+=========+======================+===============+===============+=================+
| 01 | Servidor Luanti (Voxel FOSS)   | ``01-luanti-tofu`` | v1.0.0  | Cloud VPS (2c / 2GB) | ~$0.033 / hr  | 1.0 hrs       | **$0.03**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 02 | Caddy + Vaultwarden (Podman)   | ``02-caddy-podman``| v1.0.0  | Small VPS (1-2c/2GB) | ~$0.015 / hr  | 2.0 hrs       | **$0.03**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 03 | Automatización con Ansible     | ``03-ansible``     | v1.0.0  | Small VPS (1-2c/2GB) | ~$0.015 / hr  | 1.0 hrs       | **$0.02**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 04 | Primitivas DNS, NTP y NFS      | ``04-primitives``  | v1.0.0  | 2x Micro / Spot BM   | ~$0.030 / hr  | 2.0 hrs       | **$0.06**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 05 | Almacenamiento S3 con Garage   | ``05-garage-s3``   | v1.0.0  | 3x Small / Spot VMs  | ~$0.045 / hr  | 3.0 hrs       | **$0.14**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 06 | Clúster K3s Mononodo           | ``06-k3s-single``  | v1.0.0  | Small VPS (2c / 4GB) | ~$0.033 / hr  | 2.0 hrs       | **$0.07**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 07 | Clúster K3s Multinodo (1CP+2W) | ``07-k3s-cluster`` | v1.0.0  | 3x Small VPS (2c/2GB)| ~$0.045 / hr  | 3.0 hrs       | **$0.14**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 08 | Inferencia IA Gemma 4 en CPU   | ``08-gemma-ai``    | v1.0.0  | Spot BM (E5-1650V3)  | ~$0.115 / hr  | 3.0 hrs       | **$0.35**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 09 | Topología de Red OpenStack     | ``09-openstack``   | v1.0.0  | 3x Spot BM (E5-1620) | ~$0.276 / hr  | 2.0 hrs       | **$0.55**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 10 | OpenStack con Kolla-Ansible    | ``10-kolla``       | v1.0.0  | 3x Spot BM (E5-1620) | ~$0.276 / hr  | 4.0 hrs       | **$1.10**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| **Gasto Total Acumulado Estimado de la Serie**                                                                              | **~$2.50 USD**  |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+

Estructura del Repositorio
--------------------------

.. code-block:: text

   ~/Projects/cherry-servers/
   ├── README.rst                         # Documentación maestra del repositorio (Estándar RST)
   ├── common/                            # Definiciones compartidas de OpenTofu (proveedor y variables)
   │   ├── provider.tf
   │   └── variables.tf
   └── 01-luanti-tofu/ ... 10-openstack-kolla/
       ├── README.md                      # Guía completa del Cómo (Markdown para difusión y lectura)
       ├── assets/
       │   └── hero.png                   # Diagrama esquemático técnico (16:9)
       ├── tofu/                          # Manifiestos planos de OpenTofu (sin módulos anidados)
       │   ├── provider.tf
       │   ├── main.tf
       │   ├── variables.tf
       │   ├── outputs.tf
       │   └── terraform.tfvars.example
       └── scripts/                       # Scripts de arranque y aprovisionamiento (.bash)

Estándares de Documentación
---------------------------

* **Justificación de reStructuredText (.rst)**: Este proyecto es 100% libre y de código
  abierto. La documentación oficial del Kernel de Linux estandariza sobre reStructuredText
  con Sphinx; si es el estándar del Kernel de Linux, es el estándar para nosotros.
* **Documentación del Repositorio**: Toda la documentación general, especificaciones y
  registros arquitectónicos se redactan en reStructuredText (``.rst``) con sangría de
  3 espacios.
* **Artefactos de Difusión y Cómos**: Los Cómos individuales se redactan en Markdown
  (``README.md``) dentro de cada subdirectorio para facilitar su lectura local (vía ``grip``
  o ``glow``) y su publicación en plataformas comunitarias.
