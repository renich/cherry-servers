=============================================================================
Serie Educativa Cherry Servers: Infraestructura Empresarial en Linux con IaC
=============================================================================

.. note::
   Currículo educativo y práctico diseñado para la comunidad de `r/LinuxEnEspanol`,
   patrocinado por Cherry Servers mediante $20 USD en créditos promocionales para
   que cada participante pueda ejecutar los 10 laboratorios sin costo.

Visión General
--------------

Este repositorio contiene el código fuente completo, scripts de automatización,
diagramas arquitectónicos y artículos para una serie de 10 laboratorios prácticos
de infraestructura empresarial.

La serie guía a administradores de sistemas, desarrolladores y entusiastas desde
los fundamentos de Infraestructura como Código (IaC) con **OpenTofu** hasta el
despliegue de clústeres de Kubernetes (K3s) y nubes privadas con OpenStack sobre
servidores dedicados Bare Metal y VPS Cloud, estandarizando sobre **CentOS Stream 10**
con **SELinux en modo Enforcing** y cumplimiento estricto del estándar **FHS 3.0** (``/srv``).

Principios Fundamentales
------------------------

* **Control Estricto de Costos y Dimensionamiento Justo**: Cada laboratorio está
  diseñado para costar centavos por hora. La ejecución completa de los 10 laboratorios
  consume aproximadamente **~$2.43 USD en total**, dejando más de **$17.50 USD de crédito
  intacto** para la exploración personal del estudiante.
* **Infraestructura Declarativa y FOSS**: Código 100% reproducible y abierto con OpenTofu.
* **Estándares Unix y FHS 3.0+**: Aislamiento estricto de servicios bajo ``/srv/<servicio>``
  con cuentas dedicadas de sistema (``/sbin/nologin``) y hardening en Systemd (``ProtectHome=true``,
  ``ProtectSystem=full``).
* **Postura Empresarial con SELinux**: Operación continua bajo modo Enforcing mediante
  etiquetado correcto de contextos (``restorecon``), sin desactivar la seguridad.
* **Disciplina de Destrucción**: Flujo obligatorio de ``tofu destroy`` al final de cada
  guía para evitar costos por recursos huérfanos.

Matriz de Laboratorios y Presupuesto
------------------------------------

+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| #  | Tema del Laboratorio           | Rama de Git        | Versión | Tipo de Servidor     | Costo / Hora  | Tiempo Estim. | Costo / Corrida |
+====+================================+====================+=========+======================+===============+===============+=================+
| 01 | Servidor Luanti (Voxel FOSS)   | ``01-luanti-tofu`` | v1.0.0  | Cloud VPS (2c / 4GB) | ~$0.015 / hr  | 2.0 hrs       | **$0.03**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 02 | Caddy + Vaultwarden (Podman)   | ``02-caddy-podman``| v1.0.0  | Cloud VPS (1-2c/2GB) | ~$0.010 / hr  | 2.0 hrs       | **$0.02**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 03 | Automatización con Ansible     | ``03-ansible``     | v1.0.0  | Cloud VPS (1-2c/2GB) | ~$0.010 / hr  | 1.0 hrs       | **$0.01**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 04 | Primitivas DNS, NTP y NFS      | ``04-primitives``  | v1.0.0  | 2x Micro / Spot BM   | ~$0.030 / hr  | 2.0 hrs       | **$0.06**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 05 | Almacenamiento S3 con Garage   | ``05-garage-s3``   | v1.0.0  | 3x Small / Spot VMs  | ~$0.045 / hr  | 3.0 hrs       | **$0.14**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 06 | Clúster K3s Mononodo           | ``06-k3s-single``  | v1.0.0  | Cloud VPS (2c / 4GB) | ~$0.015 / hr  | 2.0 hrs       | **$0.03**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 07 | Clúster K3s Multinodo (1CP+2W) | ``07-k3s-cluster`` | v1.0.0  | 3x Small VPS (2c/2GB)| ~$0.045 / hr  | 3.0 hrs       | **$0.14**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 08 | Inferencia IA Gemma 4 en CPU   | ``08-gemma-ai``    | v1.0.0  | Spot BM (E5-1650V3)  | ~$0.115 / hr  | 3.0 hrs       | **$0.35**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 09 | Topología de Red OpenStack     | ``09-openstack``   | v1.0.0  | 3x Spot BM (E5-1620) | ~$0.276 / hr  | 2.0 hrs       | **$0.55**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| 10 | OpenStack con Kolla-Ansible    | ``10-kolla``       | v1.0.0  | 3x Spot BM (E5-1620) | ~$0.276 / hr  | 4.0 hrs       | **$1.10**       |
+----+--------------------------------+--------------------+---------+----------------------+---------------+---------------+-----------------+
| **Gasto Total Acumulado Estimado de la Serie**                                                                              | **~$2.43 USD**  |
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
       ├── README.md                      # Publicación para Reddit (Markdown para r/LinuxEnEspanol)
       ├── assets/
       │   └── hero.png                   # Diagrama esquemático técnico (16:9)
       ├── tofu/                          # Manifiestos planos de OpenTofu (sin módulos anidados)
       │   ├── provider.tf
       │   ├── main.tf
       │   ├── variables.tf
       │   ├── outputs.tf
       │   └── terraform.tfvars.example
       └── scripts/                       # Scripts de arranque y aprovisionamiento (FHS 3.0)

Estándares de Documentación
---------------------------

* **Justificación de reStructuredText (.rst)**: Este proyecto es 100% libre y de código
  abierto. La documentación oficial del Kernel de Linux estandariza sobre reStructuredText
  con Sphinx; si es el estándar del Kernel de Linux, es el estándar para nosotros.
* **Documentación del Repositorio**: Toda la documentación general, especificaciones y
  registros arquitectónicos se redactan en reStructuredText (``.rst``) con sangría de
  3 espacios.
* **Artefactos de Publicación**: Los tutoriales individuales destinados a ``r/LinuxEnEspanol``
  se redactan exclusivamente en Markdown (``README.md``) dentro de cada subdirectorio para
  facilitar su copia y publicación directa en Reddit.
