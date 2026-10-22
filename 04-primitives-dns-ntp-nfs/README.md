# Cómo desplegar las primitivas de red y almacenamiento DNS, NTP y NFSv4 en CentOS Stream 10

> **Cómo 04: Primitivas de Infraestructura DNS con BIND 9, NTP con Chrony y NFSv4.2 con SELinux**
>
> * **Versión:** `v1.0.0`
> * **Fecha:** `2026-10-22`
> * **Rama de Git:** [`master/04-primitives-dns-ntp-nfs`](https://gitlab.com/renich/cherry-servers/-/tree/master/04-primitives-dns-ntp-nfs)
> * **Licencia:** [`GFDL-1.3-or-later`](../LICENSE)
> * **Tipo de instancia:** 2x Cloud VPS 1 Gen 2 con 1 vCore, 1 GB RAM y 20 GB SSD por nodo
> * **Costo por hora:** ~$0.030 EUR/hora (~$0.034 USD/hora por ambos nodos)
> * **Tiempo promedio:** 2 horas
> * **Gasto estimado total:** ~$0.06 USD

---

¡Hola! 👋

Te doy una calurosa bienvenida al **cuarto Cómo** de nuestra serie práctica de infraestructura empresarial y administración de sistemas en Linux para la comunidad de software libre de Latinoamérica y de habla hispana.

En los tres primeros laboratorios aprendiste a construir y automatizar servicios sobre un único servidor: desplegaste un motor de juegos voxel con **Luanti** en el Cómo 01, publicaste aplicaciones en contenedores aislados con **Podman Quadlets y Caddy** en el Cómo 02 y dominaste la gestión declarativa e idempotente de configuraciones con **Ansible** en el Cómo 03.

A partir de este momento das el salto hacia los **sistemas distribuidos multi-nodo**. Antes de construir almacenamiento de objetos distribuido S3 en el Cómo 05, clústeres de Kubernetes con K3s en los Cómos 06 y 07 o nubes privadas con OpenStack en los Cómos 09 y 10, todo centro de datos profesional descansa sobre **tres primitivas fundamentales de red y almacenamiento**:

1. **Resolución de Nombres Interna con BIND 9 y DNS:** En una infraestructura real, memorizar direcciones IP o editar archivos `/etc/hosts` a mano en decenas de servidores es insostenible. Necesitas un servidor DNS autoritativo y recursivo interno que gobierne tu propio dominio `linenes.tld`, traduzca nombres de servicio como `ns1`, `ntp` y `nfs` a direcciones IP privadas y resuelva consultas inversas `PTR`.
1. **Sincronización de Tiempo de Precisión con Chrony y NTP:** Los protocolos modernos de seguridad y consenso distribuido como certificados TLS, Kerberos, Raft en Kubernetes, CRDTs en Garage S3 y correlación de bitácoras en `journald` fallan de forma crítica si los relojes de tus servidores difieren entre sí. Configurarás tu propio servidor NTP de estrato interno para mantener todos tus nodos sincronizados al milisegundo.
1. **Almacenamiento Compartido en Red con NFSv4.2 Puro:** Aprenderás a exportar y montar sistemas de archivos compartidos a través de la red bajo el estándar **FHS 3.0** en `/srv/nfs/compartido`, operando exclusivamente sobre **NFSv4.2** con un único puerto TCP `2049`, sin los antiguos demonios inseguros `rpcbind` ni `rpc.statd` de NFSv3, y protegido de principio a fin por **SELinux en modo Enforcing** con contexto `nfs_t` y aislamiento de privilegios `root_squash`.

Siguiendo nuestra filosofía pedagógica **«Manual Primero, Automatización Después»**, primero construirás y verificarás paso a paso estas tres primitivas entre dos servidores conectados por red privada vía SSH, y posteriormente automatizarás el despliegue completo de la topología multi-nodo con un solo comando mediante **OpenTofu**.

---

## 1. Prerrequisitos del Laboratorio

Para realizar esta práctica trabajarás con **dos servidores con CentOS Stream 10**:

* **Nodo 0, Servidor de Primitivas `0.primitivas.linenes.tld`:** Actuará como servidor autoritativo DNS con BIND 9, servidor maestro de tiempo NTP con Chrony y servidor de almacenamiento compartido NFSv4.2.
* **Nodo 1, Cliente de Verificación `1.primitivas.linenes.tld`:** Consumirá el DNS interno para resolver nombres, sincronizará su reloj contra `ntp.linenes.tld` y montará el almacenamiento compartido desde `nfs.linenes.tld`.

### A. Tu Saldo de Regalo de $20 USD en Cherry Servers

Para que puedas desplegar ambos servidores en la nube y practicar con infraestructura real sin costo de tu bolsillo, contamos con el patrocinio directo de **Cherry Servers** para nuestra comunidad:

* 🎁 **Regístrate aquí:** [Portal de bienvenida de Cherry Servers ($20 USD de crédito)](https://portal.cherryservers.com/register?promo_code=LinuxEnEspanol)
* 🏷️ **Código promocional:** `LinuxEnEspanol`

Al crear tu cuenta con ese enlace y código, recibirás **$20 USD de saldo de regalo**. Dado que cada instancia **Cloud VPS 1** cuesta apenas ~$0.015 EUR/hora, ejecutar los dos servidores de este laboratorio durante dos horas completas consume alrededor de **$0.06 USD** (seis centavos de dólar). Con tus $20 USD de regalo tienes saldo de sobra para realizar los 10 Cómos de toda la serie y repetir las prácticas cuantas veces quieras, recordando siempre destruir los recursos al terminar (`tofu destroy`).

### B. Tu Estación de Trabajo o Nodo de Control

Puedes conectarte a tus dos servidores desde tu computadora personal con **Fedora Linux** (o cualquier distribución GNU/Linux) o desde la estación de control con **CentOS Stream 10** que preparaste en el Cómo 03.

Asegúrate de contar con tu llave criptográfica **Ed25519** (`~/.ssh/id_ed25519.pub`) y con `ssh-agent` activo en tu terminal para no escribir tu frase de paso en cada conexión:

```bash
# Si aún no tienes tu par de llaves Ed25519, genéralo:
ssh-keygen -t ed25519 -C "tu_correo@ejemplo.com"

# Inicia el agente SSH en tu sesión actual y carga tu llave privada:
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
ssh-add -l
```

Instala en tu máquina local las herramientas para la fase de automatización con OpenTofu:

* **En Fedora Linux:**

  ```bash
  sudo dnf -y install openssh-clients git-core curl jq opentofu
  ```

* **En CentOS Stream 10:**

  ```bash
  sudo dnf -y install epel-release dnf-plugins-core
  sudo dnf -y install openssh-clients git-core curl jq
  curl --proto '=https' --tlsv1.2 -fsSL -o install-opentofu.sh https://get.opentofu.org/install-opentofu.sh
  sudo bash install-opentofu.sh --install-method rpm
  rm -f install-opentofu.sh
  ```

### C. Creación de los Dos Nodos para la Práctica Manual

Despliega dos instancias **Cloud VPS 1** `B1-1-1gb-20s-shared` con **CentOS Stream 10** en la misma región, por ejemplo `LT-Siauliai`, dentro de tu proyecto en el portal de Cherry Servers o mediante `tofu apply` con `enable_bootstrap = false` como verás en la Sección 3, asociando tu llave pública SSH Ed25519:

1. **Primer servidor:** Asígnale el nombre de host `0.primitivas.linenes.tld`.
1. **Segundo servidor:** Asígnale el nombre de host `1.primitivas.linenes.tld`.

> **Nota para máquinas virtuales locales:**
> Si realizas la práctica en tu propio hipervisor local con KVM/libvirt o VirtualBox, asegúrate de que ambas máquinas virtuales estén conectadas al mismo puente de red privado, por ejemplo `virbr0` en el segmento `192.168.122.0/24`, para que puedan comunicarse directamente entre sí.

---

## 2. Construcción y Configuración Manual vía SSH, El Núcleo del Aprendizaje

### Paso A: Inspección de la Topología de Red Privada e Instalación de Paquetes

En la nube de Cherry Servers, cada instancia **Cloud VPS** se aprovisiona automáticamente con dos interfaces de red:

* `eth0`: Interfaz conectada a internet con tu **dirección IPv4 pública**.
* `ens4`: Interfaz conectada a la **VLAN privada interna** de tu proyecto en el rango privado RFC 1918 `10.x.x.0/24`, ideal para el tráfico interno entre tus servidores sin salir a internet.

Primero, conéctate por SSH a ambos servidores desde tu estación de trabajo para identificar sus direcciones IP privadas internas.

En una pestaña de tu terminal, conéctate al **Nodo 0**:

```bash
ssh root@<IP_PUBLICA_NODO_0>
```

Configura su nombre de host canónico y consulta sus interfaces de red y el estado de SELinux:

```bash
hostnamectl set-hostname 0.primitivas.linenes.tld
hostnamectl
ip -4 -o addr show scope global
sestatus
```

Observa la salida de `ip -4 -o addr show scope global`:

```text
2: eth0    inet 84.32.110.69/32 scope global noprefixroute eth0
3: ens4    inet 10.198.141.17/24 brd 10.198.141.255 scope global noprefixroute ens4
```

Toma nota de la dirección IP privada de `ens4`, que en nuestro ejemplo es `10.198.141.17`, y de los primeros tres octetos de tu subred privada `10.198.141`. Si haces lo mismo en el **Nodo 1**, verás que tiene su propia IP en la misma subred privada, por ejemplo `10.198.141.33`.

> **Importante:** A lo largo de esta guía utilizarás `10.198.141.17` como referencia para el **Nodo 0** y `10.198.141.33` para el **Nodo 1** en la subred `10.198.141.0/24` y zona inversa `141.198.10.in-addr.arpa`. Sustituye estos valores por las direcciones IP privadas que Cherry Servers haya asignado a tus instancias.

En el **Nodo 0** `0.primitivas.linenes.tld`, instala los paquetes RPM oficiales para las tres primitivas y las herramientas de políticas de SELinux y Firewalld:

```bash
dnf -y install bind bind-utils chrony nfs-utils policycoreutils-python-utils firewalld dnf-automatic
```

**¿Qué función cumple cada paquete instalado?**

* `bind`: El demonio `named` de ISC BIND 9 (servidor DNS autoritativo y recursivo).
* `bind-utils`: Herramientas de diagnóstico y administración DNS (`dig`, `nsupdate`, `host`, `delv`).
* `chrony`: Implementación moderna, ligera y de alta precisión del protocolo NTP (`chronyd` y `chronyc`).
* `nfs-utils`: Servidor y cliente en espacio de usuario para el sistema de archivos de red NFSv4 del kernel de Linux (`rpc.mountd`, `exportfs`, `mount.nfs4`).
* `policycoreutils-python-utils`: Proporciona la utilidad `semanage` para declarar contextos persistentes de SELinux.
* `firewalld`: Demonio de cortafuegos dinámico basado en zonas sobre `nftables`.

---

### Paso B: Segmentación de Zonas en Firewalld entre public e internal

Un error común y peligroso en tutoriales básicos consiste en abrir los puertos de DNS `53`, NTP `123` y NFS `2049` en la zona `public` del cortafuegos. Hacer eso expone tu servidor DNS recursivo, tu reloj NTP y tu sistema de archivos compartido a todo internet, convirtiendo tu máquina en blanco de ataques de amplificación DNS/NTP o intentos de montaje no autorizados.

La arquitectura correcta en **Firewalld** aprovecha la **segmentación por zonas basadas en origen**:

1. La zona `public`, asignada por defecto al tráfico que entra desde internet por `eth0`, permanece cerrada permitiendo únicamente `ssh`.
1. Asocias los rangos de red privada interna **RFC 1918** `10.0.0.0/8`, `192.168.0.0/16` y `172.16.0.0/12` a la zona `internal`.
1. Habilitas los servicios `dns`, `ntp` y `nfs` **exclusivamente dentro de la zona `internal`**.

Ejecuta en el **Nodo 0** `0.primitivas.linenes.tld`:

```bash
# 1. Asegurar que el servicio firewalld esté habilitado y en ejecución
systemctl --now enable firewalld

# 2. Asociar las redes privadas RFC 1918 a la zona 'internal'
firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
firewall-cmd --permanent --zone=internal --add-source=192.168.0.0/16
firewall-cmd --permanent --zone=internal --add-source=172.16.0.0/12

# 3. Permitir DNS (53/tcp,udp), NTP (123/udp) y NFSv4 (2049/tcp) solo en la zona 'internal'
firewall-cmd --permanent --zone=internal --add-service=dns
firewall-cmd --permanent --zone=internal --add-service=ntp
firewall-cmd --permanent --zone=internal --add-service=nfs

# 4. Recargar Firewalld para aplicar las reglas en nftables
firewall-cmd --reload
```

Verifica cómo quedaron separadas ambas zonas:

```bash
firewall-cmd --zone=internal --list-all
firewall-cmd --zone=public --list-all
```

En la salida comprobarás que cualquier paquete originado desde la red privada interna (`10.0.0.0/8`) es procesado de forma determinista por la zona `internal` con acceso a `dns`, `nfs` y `ntp`, mientras que el tráfico público externo en `public` solo alcanza `ssh`.

---

### Paso C: Primitiva 1, Servidor DNS Autoritativo y Recursivo con BIND 9

Configurarás **BIND 9** con `named.service` en el **Nodo 0** para cumplir dos funciones simultáneas dentro de tu red privada:

1. **Autoritativo para `linenes.tld` y su zona inversa:** Responderá con autoridad sobre los nombres de tus servidores `0.primitivas.linenes.tld`, `1.primitivas.linenes.tld`, `ns1.linenes.tld`, `ntp.linenes.tld` y `nfs.linenes.tld`, junto con sus direcciones IP privadas.
1. **Recursivo con reenviadores para dominios externos:** Cuando un nodo interno consulte un dominio de internet como `centos.org`, BIND 9 resolverá la consulta utilizando reenviadores rápidos `1.1.1.1` y `9.9.9.9` y almacenará la respuesta en caché.

#### 1. Crear el archivo principal `/etc/named.conf`

En el **Nodo 0**, define las variables con tu IP privada y los octetos de tu subred para generar la configuración sin errores de transcripción:

```bash
# Detecta automáticamente la IP privada RFC 1918 de tu Nodo 0
SERVER_PRIV_IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
IFS='.' read -r OCT1 OCT2 OCT3 OCT4 <<< "${SERVER_PRIV_IP}"
REV_ZONE="${OCT3}.${OCT2}.${OCT1}.in-addr.arpa"

printf 'IP Privada Nodo 0: %s | Zona Inversa: %s\n' "${SERVER_PRIV_IP}" "${REV_ZONE}"
```

Ahora genera el archivo `/etc/named.conf`:

```bash
cat << EOF > /etc/named.conf
// =============================================================================
// Configuración de BIND 9: DNS Autoritativo y Recursivo Interno (linenes.tld)
// =============================================================================

acl "red_interna" {
    127.0.0.0/8;
    ::1;
    10.0.0.0/8;
    192.168.0.0/16;
    172.16.0.0/12;
};

options {
    // Escuchar exclusivamente en loopback y en la IP privada (nunca en la IP pública WAN)
    listen-on port 53 { 127.0.0.1; ${SERVER_PRIV_IP}; };
    listen-on-v6 port 53 { ::1; };

    directory          "/var/named";
    dump-file          "/var/named/data/cache_dump.db";
    statistics-file    "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file      "/var/named/data/named.secroots";
    recursing-file     "/var/named/data/named.recursing";

    // Restringir consultas y recursión estrictamente a la ACL de nuestra red privada
    allow-query     { "red_interna"; };
    allow-recursion { "red_interna"; };
    recursion yes;

    // Reenviadores externos para dominios fuera de linenes.tld
    forwarders {
        1.1.1.1;
        9.9.9.9;
    };
    forward first;

    dnssec-validation yes;

    managed-keys-directory "/var/named/dynamic";
    geoip-directory "/usr/share/GeoIP";

    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";

    include "/etc/crypto-policies/back-ends/bind.config";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

// Zona directa autoritativa para nuestro laboratorio
zone "linenes.tld" IN {
    type primary;
    file "linenes.tld.zone";
    allow-update { "red_interna"; };
};

// Zona inversa autoritativa para nuestra subred privada /24
zone "${REV_ZONE}" IN {
    type primary;
    file "linenes.tld.rev";
    allow-update { "red_interna"; };
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF
```

**Puntos clave de arquitectura en `/etc/named.conf`:**

* `listen-on port 53 { 127.0.0.1; ${SERVER_PRIV_IP}; };`: Ordena al demonio `named` abrir el socket TCP/UDP 53 únicamente en la interfaz local y en la interfaz privada `ens4`. Así, además del bloqueo en Firewalld, el proceso ni siquiera escucha en la IP pública `eth0`.
* `allow-query` y `allow-recursion`: Limitan cualquier consulta y resolución recursiva a los bloques definidos en `acl "red_interna"`.
* `allow-update { "red_interna"; };`: Permite que los nodos clientes de nuestra red privada registren dinámicamente sus propios registros `A` y `PTR` mediante la herramienta estándar `nsupdate` (RFC 2136). En el Reto 1 aprenderás a blindar estas actualizaciones dinámicas con llaves criptográficas **TSIG**.

#### 2. Crear los archivos de zona directa e inversa en `/var/named`

En BIND 9, los archivos de zona residen bajo `/var/named/`, directorio que cuenta por defecto con el contexto de SELinux `named_zone_t`.

Crea el archivo de zona directa `/var/named/linenes.tld.zone`:

```bash
cat << EOF > /var/named/linenes.tld.zone
\$TTL 86400
@   IN  SOA ns1.linenes.tld. admin.linenes.tld. (
            2026102201  ; Serial (AAAAMMDDNN)
            3600        ; Refresh (1 hora)
            1800        ; Retry (30 minutos)
            604800      ; Expire (1 semana)
            86400 )     ; Minimum TTL (1 día)

; Servidor de nombres autoritativo de la zona (debe apuntar a un registro A, nunca a un CNAME)
@               IN  NS      ns1.linenes.tld.

; Registros A de nodos de infraestructura
ns1             IN  A       ${SERVER_PRIV_IP}
0.primitivas    IN  A       ${SERVER_PRIV_IP}

; Alias canónicos de servicios (CNAME)
ntp             IN  CNAME   0.primitivas.linenes.tld.
nfs             IN  CNAME   0.primitivas.linenes.tld.
EOF
```

> **Detalle técnico sobre RFC 2181:**
> En el estándar DNS, un registro `NS` (*Name Server*) jamás debe apuntar a un alias `CNAME`; siempre debe apuntar a un nombre que posea un registro `A` o `AAAA` propio (`ns1 IN A ...`). En cambio, para servicios funcionales como `ntp.linenes.tld` y `nfs.linenes.tld`, usar registros `CNAME` que apunten a `0.primitivas.linenes.tld.` es una excelente práctica: si el día de mañana decides migrar el almacenamiento NFS a un servidor dedicado distinto, solo cambias el `CNAME` de `nfs` en el DNS sin tocar los archivos `/etc/fstab` de tus clientes.

Ahora crea el archivo de zona inversa `/var/named/linenes.tld.rev`:

```bash
cat << EOF > /var/named/linenes.tld.rev
\$TTL 86400
@   IN  SOA ns1.linenes.tld. admin.linenes.tld. (
            2026102201  ; Serial (AAAAMMDDNN)
            3600        ; Refresh (1 hora)
            1800        ; Retry (30 minutos)
            604800      ; Expire (1 semana)
            86400 )     ; Minimum TTL (1 día)

; Servidor de nombres autoritativo
@       IN  NS      ns1.linenes.tld.

; Registros PTR (Resolución Inversa: último octeto -> FQDN con punto final)
${OCT4} IN  PTR     0.primitivas.linenes.tld.
EOF
```

#### 3. Permisos, Contextos SELinux y Validación Sintáctica

Ajusta los permisos y propietarios para que el usuario de sistema `named` pueda leer `/etc/named.conf` y crear archivos de bitácora dinámica `.jnl` en `/var/named/`, habilita el booleano de SELinux `named_write_master_zones` y restaura los contextos de seguridad:

```bash
chmod 770 /var/named
chown root:named /etc/named.conf
chmod 640 /etc/named.conf

chown named:named /var/named/linenes.tld.zone /var/named/linenes.tld.rev
chmod 640 /var/named/linenes.tld.zone /var/named/linenes.tld.rev

setsebool -P named_write_master_zones on
restorecon -Rv /etc/named.conf /var/named
```

Antes de iniciar el servicio, valida rigurosamente la sintaxis de configuración y la integridad de ambas zonas con las utilidades nativas de BIND 9:

```bash
named-checkconf -z /etc/named.conf
named-checkzone -i full linenes.tld /var/named/linenes.tld.zone
named-checkzone -i full "${REV_ZONE}" /var/named/linenes.tld.rev
```

Verás que ambas zonas cargan el serial `2026102201` y devuelven `OK`. Habilita e inicia el servicio `named.service` en Systemd:

```bash
systemctl --now enable named.service
systemctl --no-pager status named.service
```

Realiza una prueba local de resolución directa, de alias `CNAME` y de resolución inversa con `dig`:

```bash
dig @"${SERVER_PRIV_IP}" 0.primitivas.linenes.tld A +short
dig @"${SERVER_PRIV_IP}" ntp.linenes.tld A +short
dig @"${SERVER_PRIV_IP}" nfs.linenes.tld A +short
dig @"${SERVER_PRIV_IP}" -x "${SERVER_PRIV_IP}" +short
```

---

### Paso D: Primitiva 2, Servidor de Tiempo de Precisión con Chrony y NTP

En **CentOS Stream 10**, el demonio `chronyd` viene instalado por defecto como cliente NTP, pero tiene deshabilitada la recepción de peticiones de otros nodos.

Configurarás `/etc/chrony.conf` en el **Nodo 0** para que:

1. Sincronice su propio reloj contra el *pool* global de servidores atómicos `2.centos.pool.ntp.org` usando el modificador `iburst`, que envía una ráfaga inicial de paquetes para sincronizar en pocos segundos al arrancar.
1. Autorice consultas NTP entrantes desde tu red privada con `allow 10.0.0.0/8`, `192.168.0.0/16` y `172.16.0.0/12`.
1. Active `local stratum 10`: si en algún momento el centro de datos pierde salida hacia internet, el **Nodo 0** continuará sirviendo una referencia de tiempo coherente a todos los nodos del clúster para evitar que sus relojes diverjan entre sí.

Ejecuta en el **Nodo 0** `0.primitivas.linenes.tld`:

```bash
cat << 'EOF' > /etc/chrony.conf
# =============================================================================
# Configuración de Chrony: Servidor NTP de Estrato Interno (ntp.linenes.tld)
# =============================================================================
pool 2.centos.pool.ntp.org iburst
sourcedir /run/chrony-dhcp
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony

# Permitir sincronización de clientes NTP desde redes privadas RFC 1918
allow 10.0.0.0/8
allow 192.168.0.0/16
allow 172.16.0.0/12

# Mantener referencia de estrato local si se pierde conectividad externa
local stratum 10
EOF

# Restaurar contexto SELinux (chronyd_conf_t) y reiniciar el servicio
restorecon -v /etc/chrony.conf
systemctl --now enable chronyd.service
systemctl restart chronyd.service
```

Comprueba el estado de sincronización y las fuentes de tiempo con `chronyc`:

```bash
chronyc tracking
chronyc sources -v
```

En `chronyc sources -v` observarás las fuentes externas con el indicador `^*` (fuente primaria seleccionada) y `^+` (fuentes combinadas de respaldo).

---

### Paso E: Primitiva 3, Servidor NFSv4.2 Puro bajo FHS 3.0 y SELinux Enforcing

Históricamente, configurar NFS en versiones antiguas como NFSv2 y NFSv3 era complejo para los administradores de sistemas: requería abrir el demonio `rpcbind` en los puertos `111/tcp` y `111/udp`, `rpc.mountd` en el puerto `20048`, `rpc.statd` y puertos efímeros para el bloqueo de archivos `lockd`.

**NFSv4.2**, el estándar moderno en CentOS Stream 10, rediseña el protocolo por completo:

* **Un único puerto TCP `2049/tcp`:** El montaje, el control de bloqueos, las listas de control de acceso y la transferencia de datos viajan multiplexados dentro de una sola conexión TCP en el puerto `2049`. No necesita `rpcbind`.
* **Soporte nativo para etiquetas SELinux:** NFSv4.2 transporta los atributos extendidos de seguridad `security.selinux` entre el servidor y los clientes.
* **Aislamiento de superusuario `root_squash`:** Por seguridad, si el usuario `root` con UID `0` de un nodo cliente intenta escribir o modificar archivos en el recurso compartido, el servidor NFSv4 degrada automáticamente su identidad a la cuenta sin privilegios `nobody` con UID `65534`, impidiendo que un cliente comprometido tome control de archivos de `root` en el servidor de almacenamiento.

#### 1. Estructura de directorios bajo FHS 3.0 y contexto SELinux `nfs_t`

Siguiendo el estándar **FHS 3.0**, crearás el árbol de almacenamiento compartido en `/srv/nfs/compartido`. Asignarás la propiedad del directorio `compartido` a `nobody:nobody` para comprobar de forma transparente cómo opera el mapeo de `root_squash`:

```bash
# 1. Crear jerarquía bajo /srv/nfs
mkdir -p /srv/nfs/compartido
chown root:root /srv/nfs
chmod 755 /srv/nfs
chown nobody:nobody /srv/nfs/compartido
chmod 755 /srv/nfs/compartido

# 2. Crear un archivo testigo inicial en el servidor
cat << EOF > /srv/nfs/compartido/bienvenida.txt
Almacenamiento compartido NFSv4.2 activo desde $(hostname) (${SERVER_PRIV_IP}).
SELinux en modo Enforcing con contexto nfs_t bajo FHS 3.0.
EOF
chown nobody:nobody /srv/nfs/compartido/bienvenida.txt
chmod 644 /srv/nfs/compartido/bienvenida.txt
```

Por defecto, cualquier subdirectorio nuevo creado dentro de `/srv` recibe la etiqueta genérica `var_t` de SELinux. Para aplicar el principio de mínimo privilegio bajo modo **Enforcing** sin depender de booleanos globales sobre todo el sistema de archivos, declara una regla persistente con `semanage fcontext` asignando el tipo específico `nfs_t` a `/srv/nfs` y aplícala con `restorecon`:

```bash
# Registrar regla persistente en la política activa de SELinux
semanage fcontext -a -t nfs_t "/srv/nfs(/.*)?"

# Aplicar el nuevo contexto recursivamente en el disco
restorecon -Rv /srv/nfs

# Verificar el contexto SELinux aplicado
ls -ldZ /srv/nfs /srv/nfs/compartido
```

Verás que el contexto cambió limpiamente a `system_u:object_r:nfs_t:s0` o `unconfined_u:object_r:nfs_t:s0`, acotando el acceso del servidor NFS estrictamente al árbol `/srv/nfs`.

#### 2. Endurecer `/etc/nfs.conf` para operar exclusivamente en NFSv4.1/v4.2

Configura `/etc/nfs.conf` para deshabilitar por completo los protocolos obsoletos (`vers3=n` y `vers4.0=n`) y aceptar únicamente **NFSv4.1 y NFSv4.2**:

```bash
cat << 'EOF' > /etc/nfs.conf
[general]
[nfsd]
vers3=n
vers4=y
vers4.0=n
vers4.1=y
vers4.2=y
rdma=n
[mountd]
manage-gids=y
EOF

restorecon -v /etc/nfs.conf
```

#### 3. Definir la exportación en `/etc/exports` e iniciar el servicio

Declara el recurso exportado en `/etc/exports`:

```bash
cat << 'EOF' > /etc/exports
/srv/nfs/compartido 10.0.0.0/8(rw,sync,no_subtree_check,root_squash,sec=sys) 192.168.0.0/16(rw,sync,no_subtree_check,root_squash,sec=sys) 172.16.0.0/12(rw,sync,no_subtree_check,root_squash,sec=sys)
EOF

restorecon -v /etc/exports
```

**Significado de cada bandera en `/etc/exports`:**

* `rw`: Permite operaciones de lectura y escritura.
* `sync`: Garantiza integridad de datos confirmando las escrituras en disco antes de responder al cliente (previene corrupción ante caídas eléctricas).
* `no_subtree_check`: Desactiva la verificación costosa de subárboles de inodos, mejorando el rendimiento y la estabilidad cuando se renombran archivos abiertos.
* `root_squash`: Mapea el UID/GID `0` (`root`) de los clientes remotos al usuario anónimo `nobody` (`65534`).
* `sec=sys`: Utiliza autenticación UNIX estándar de UID/GID con `manage-gids=y` en `mountd` para resolver hasta miles de grupos suplementarios en el servidor sin el límite clásico de 16 grupos de RPC.

Enmascara los servicios legados `rpcbind` y `rpc-statd`, innecesarios en NFSv4 puro, e inicia `nfs-server.service`:

```bash
systemctl --now mask rpcbind.service rpcbind.socket rpc-statd.service
systemctl --now enable nfs-server.service
systemctl restart nfs-server.service
exportfs -rav
```

Verifica las tablas de exportación y comprueba qué versiones del protocolo están activas en el kernel:

```bash
exportfs -v
cat /proc/fs/nfsd/versions
ss -tulpn | grep -E '(:53|:123|:2049)'
```

Observa la salida de `/proc/fs/nfsd/versions`:

```text
-3 +4 -4.0 +4.1 +4.2
```

El signo `-3` y `-4.0` confirman que el kernel rechaza versiones antiguas y opera exclusivamente en **NFSv4.1 y NFSv4.2** sobre el puerto `2049/tcp`.

---

### Paso F: Configuración y Verificación desde el Nodo Cliente `1.primitivas.linenes.tld`

Ahora abre otra pestaña en tu terminal y conéctate por SSH al **Nodo 1**:

```bash
ssh root@<IP_PUBLICA_NODO_1>
```

Configura su nombre de host canónico, instala las herramientas cliente y asegúrate de tener `firewalld` activo:

```bash
hostnamectl set-hostname 1.primitivas.linenes.tld
dnf -y install bind-utils chrony nfs-utils firewalld dnf-automatic
systemctl --now enable firewalld
```

Define en una variable la dirección IP privada de tu **Nodo 0**, que en nuestro ejemplo es `10.198.141.17`:

```bash
SERVER_PRIV_IP="10.198.141.17"
```

#### 1. Configurar el Cliente DNS con NetworkManager y Registrar el Nodo con `nsupdate`

Nunca edites `/etc/resolv.conf` directamente a mano en distribuciones empresariales modernas, ya que **NetworkManager** administra ese archivo y sobrescribirá tus cambios al renovar concesiones de red o reiniciar el servicio.

Utiliza `nmcli` para configurar de forma persistente el servidor DNS interno `${SERVER_PRIV_IP}` con prioridad máxima y el dominio de búsqueda `linenes.tld` en la conexión principal del nodo:

```bash
DEFAULT_DEV=$(ip -4 route show default | awk '{print $5; exit}')
PRIMARY_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="${DEFAULT_DEV}" '$NF == dev {sub(/:[^:]*$/, ""); print; exit}')
nmcli connection modify "${PRIMARY_CON}" ipv4.dns "${SERVER_PRIV_IP}" ipv4.dns-search "linenes.tld" ipv4.ignore-auto-dns yes ipv4.dns-priority 10
nmcli connection up "${PRIMARY_CON}"
```

Comprueba que `/etc/resolv.conf` ahora apunta a tu servidor DNS interno:

```bash
cat /etc/resolv.conf
```

Ahora registra dinámicamente la dirección IP privada de este **Nodo 1** `1.primitivas.linenes.tld` tanto en la zona directa como en la zona inversa de BIND 9 utilizando `nsupdate`:

```bash
CLIENT_PRIV_IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
IFS='.' read -r C_OCT1 C_OCT2 C_OCT3 C_OCT4 <<< "${CLIENT_PRIV_IP}"
CLIENT_REV_ZONE="${C_OCT3}.${C_OCT2}.${C_OCT1}.in-addr.arpa"

nsupdate << EOF
server ${SERVER_PRIV_IP}
zone linenes.tld
update delete 1.primitivas.linenes.tld. A
update add 1.primitivas.linenes.tld. 86400 A ${CLIENT_PRIV_IP}
send
zone ${CLIENT_REV_ZONE}
update delete ${C_OCT4}.${CLIENT_REV_ZONE}. PTR
update add ${C_OCT4}.${CLIENT_REV_ZONE}. 86400 PTR 1.primitivas.linenes.tld.
send
EOF
```

Verifica desde el cliente que todos los nombres y direcciones inversas resuelven sin especificar `@servidor`:

```bash
dig 0.primitivas.linenes.tld +short
dig 1.primitivas.linenes.tld +short
dig ntp.linenes.tld +short
dig nfs.linenes.tld +short
dig -x "${SERVER_PRIV_IP}" +short
dig -x "${CLIENT_PRIV_IP}" +short
```

¡Tu infraestructura ya cuenta con resolución de nombres directa e inversa funcional!

#### 2. Sincronizar el Reloj del Cliente contra `ntp.linenes.tld`

Observa cómo ahora puedes usar directamente el nombre DNS **`ntp.linenes.tld`** en lugar de direcciones IP fijas. Configura `/etc/chrony.conf` en el **Nodo 1** dando preferencia con `prefer` a tu servidor NTP interno:

```bash
cat << 'EOF' > /etc/chrony.conf
# =============================================================================
# Configuración de Chrony (Cliente): Sincronización contra ntp.linenes.tld
# =============================================================================
server ntp.linenes.tld iburst prefer
pool 2.centos.pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
EOF

restorecon -v /etc/chrony.conf
systemctl --now enable chronyd.service
systemctl restart chronyd.service
```

Espera 5 segundos y verifica las fuentes de tiempo del cliente:

```bash
chronyc sources -v
chronyc tracking
```

Verás en la primera línea de `chronyc sources -v` a `^* 0.primitivas.linenes.tld` seleccionado con el asterisco `*` como la fuente de reloj preferida y de menor latencia (menos de 1 milisegundo a través de la VLAN privada).

#### 3. Montar el Almacenamiento Compartido desde `nfs.linenes.tld` con NFSv4.2

En el **Nodo 1**, crea el directorio local de montaje `/mnt/compartido` y declara el montaje persistente en `/etc/fstab` utilizando el nombre DNS **`nfs.linenes.tld`**:

```bash
mkdir -p /mnt/compartido

cat << 'EOF' >> /etc/fstab
nfs.linenes.tld:/srv/nfs/compartido  /mnt/compartido  nfs4  rw,relatime,vers=4.2,_netdev,x-systemd.automount  0  0
EOF
```

**¿Por qué incluyes `_netdev` y `x-systemd.automount` en `/etc/fstab`?**

* `_netdev`: Informa a Systemd que este sistema de archivos requiere que la pila de red y `network-online.target` estén activos antes de intentar el montaje durante el arranque.
* `x-systemd.automount`: Genera automáticamente una unidad `mnt-compartido.automount` en Systemd que monta el recurso bajo demanda al primer acceso y evita que el arranque del servidor cliente se bloquee si el servidor NFS se está reiniciando.

Recarga las unidades generadas por Systemd, activa el objetivo de sistemas de archivos remotos y realiza el montaje:

```bash
systemctl daemon-reload
systemctl restart remote-fs.target
mount -a
```

Verifica que el sistema de archivos esté montado con **NFSv4.2** y lee el archivo de bienvenida creado por el servidor:

```bash
df -hT /mnt/compartido
mount | grep /mnt/compartido
cat /mnt/compartido/bienvenida.txt
```

Ahora realiza la prueba de escritura desde el **Nodo 1 (Cliente)** y comprueba en acción la protección `root_squash`:

```bash
cat << EOF > /mnt/compartido/reporte-cliente.txt
Archivo escrito desde $(hostname) (${CLIENT_PRIV_IP}) mediante NFSv4.2.
Fecha UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

ls -laZ /mnt/compartido/
```

Observa el propietario de `reporte-cliente.txt` en la salida de `ls -laZ /mnt/compartido/`:

```text
-rw-r--r--. 1 nobody nobody system_u:object_r:nfs_t:s0 112 Oct 22 22:50 reporte-cliente.txt
```

A pesar de que ejecutaste el comando como `root` en el cliente, el servidor NFSv4.2 aplicó `root_squash` y almacenó el archivo bajo el usuario sin privilegios `nobody:nobody` con el contexto SELinux `nfs_t`. Si regresas a la terminal del **Nodo 0 (Servidor)** y ejecutas `cat /srv/nfs/compartido/reporte-cliente.txt`, verás instantáneamente el archivo escrito por el cliente.

---

### Paso G: Mantenimiento Continuo y Actualizaciones Automáticas con DNF5

En **CentOS Stream 10**, que utiliza **DNF5**, el archivo de configuración `/etc/dnf/automatic.conf` está empaquetado como `%ghost` y no existe en disco tras instalar el paquete hasta que se copia desde su plantilla en `/usr/share/dnf5/dnf5-plugins/automatic.conf`.

Ejecuta en **ambos nodos** `Nodo 0` y `Nodo 1` para dejar habilitadas las actualizaciones automáticas de seguridad:

```bash
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl --now enable dnf-automatic.timer
systemctl --no-pager status dnf-automatic.timer
```

---

## 3. Automatización Declarativa con OpenTofu e Infraestructura como Código

Una vez que has comprendido y ejecutado manualmente la configuración de las tres primitivas entre el servidor y el cliente, desplegarás toda la topología multi-nodo de forma 100% automatizada con **OpenTofu**.

### Clonar el Repositorio y Explorar los Manifiestos

En tu estación de trabajo o nodo de control, clona el repositorio oficial y sitúate en el directorio del **Cómo 04**:

```bash
git clone https://gitlab.com/renich/cherry-servers.git
cd cherry-servers/04-primitives-dns-ntp-nfs
```

La estructura de automatización consta de dos scripts declarativos en `scripts/` y los manifiestos planos en `tofu/`:

* `scripts/bootstrap.bash`: Configura automáticamente el **Nodo 0** `0.primitivas.linenes.tld` con Firewalld segmentado por zonas, BIND 9 autoritativo/recursivo, Chrony como servidor NTP de estrato interno y el servidor NFSv4.2 puro bajo `/srv/nfs/compartido` con SELinux en modo Enforcing.
* `scripts/bootstrap-client.bash`: Configura automáticamente el **Nodo 1** `1.primitivas.linenes.tld`, recibe de OpenTofu la dirección IP privada recién asignada al Nodo 0, espera a que BIND 9 y NFSv4.2 estén en línea, configura NetworkManager, registra sus propios registros `A` y `PTR` vía `nsupdate`, sincroniza Chrony contra `ntp.linenes.tld` y monta `nfs.linenes.tld:/srv/nfs/compartido` en `/mnt/compartido`.
* `tofu/main.tf`: Declara el grafo de dependencias entre ambos servidores. Dado que `primitivas_client` referencia la dirección IP privada de `primitivas_server` mediante `local.server_private_ip` dentro de su bloque `user_data`, OpenTofu aprovisiona primero el nodo servidor, extrae su dirección IP de la VLAN privada y la inyecta automáticamente en el script de arranque del nodo cliente.

### Configurar Variables Locales y Desplegar con `tofu apply`

Ingresa al directorio `tofu/` y crea tu archivo `terraform.tfvars` a partir de la plantilla de ejemplo:

```bash
cd tofu
cp terraform.tfvars.example terraform.tfvars
```

Edita `terraform.tfvars` con tu token de API, el ID de tu proyecto y tu llave pública SSH Ed25519. Si en algún momento deseas aprovisionar ambos nodos limpios sin ejecutar los scripts de arranque para practicar manualmente la Sección 2, basta con cambiar `enable_bootstrap = false`:

```hcl
cherry_auth_token = "TU_API_TOKEN_AQUI"
project_id        = 123456
ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... tu_correo@ejemplo.com"
server_name       = "0.primitivas.linenes.tld"
client_name       = "1.primitivas.linenes.tld"
dns_domain        = "linenes.tld"
server_image      = "centos_stream_10_64bit"
spot_instance     = false
enable_bootstrap  = true
```

> **Consejo si tu llave SSH ya estaba registrada en el portal de Cherry Servers:**
> Si agregaste previamente la misma llave SSH desde el panel web de Cherry Servers, la API devolverá el aviso `Similar key already exists` al intentar crear `cherryservers_ssh_key.deployer`. Puedes importar tu llave existente al estado de OpenTofu ejecutando `tofu import cherryservers_ssh_key.deployer <ID_DE_TU_LLAVE>` o bien generar un par de llaves dedicado para tus despliegues con OpenTofu mediante `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_tofu`.

Inicializa el proveedor, valida la sintaxis y despliega la infraestructura:

```bash
tofu init
tofu validate
tofu apply
```

Confirma escribiendo `yes`. Al finalizar el aprovisionamiento, OpenTofu mostrará las direcciones IP públicas y privadas de ambos nodos junto con los comandos directos de conexión SSH:

```text
Outputs:

client_private_ip = "10.198.141.33"
client_public_ip = "84.32.149.179"
server_private_ip = "10.198.141.17"
server_public_ip = "84.32.110.69"
ssh_client_command = "ssh root@84.32.149.179"
ssh_server_command = "ssh root@84.32.110.69"
```

Espera aproximadamente 90 segundos para que `cloud-init` concluya la ejecución de `bootstrap.bash` y `bootstrap-client.bash`, y verifica el estado completo desde tu terminal ejecutando:

```bash
ssh root@<IP_PUBLICA_CLIENTE> "dig nfs.linenes.tld +short && chronyc sources && df -hT /mnt/compartido && ls -laZ /mnt/compartido"
```

---

## 4. Destrucción de los Servidores y Control de Costos

Recuerda siempre nuestra regla de disciplina operativa en la nube: al concluir tus pruebas y retos, destruye los recursos para conservar intacto tu saldo patrocinado de $20 USD para los siguientes laboratorios de la serie:

```bash
cd tofu
tofu destroy
```

Confirma escribiendo `yes`. OpenTofu eliminará ambos servidores y liberará las direcciones IP en tu proyecto de Cherry Servers.

Finalmente, limpia las huellas SSH de tus servidores efímeros en tu archivo local `known_hosts`:

```bash
ssh-keygen -R <IP_PUBLICA_SERVIDOR>
ssh-keygen -R <IP_PUBLICA_CLIENTE>
```

---

## 5. Retos de Aprendizaje y Práctica

Pon a prueba lo aprendido con estos tres desafíos de ingeniería sin soluciones prefabricadas:

1. **Reto 1: Actualizaciones DNS Dinámicas Autenticadas con Llaves Criptográficas TSIG y `tsig-keygen`**
   * En el laboratorio permitiste actualizaciones dinámicas con `allow-update` basadas en la dirección IP de la subred privada mediante `acl "red_interna"`. En entornos de alta seguridad, autorizar por IP no es suficiente si un atacante logra conectarse a la VLAN. Investiga cómo generar una llave simétrica HMAC-SHA256 utilizando la herramienta `tsig-keygen -a hmac-sha256 actualizacion-linenes`, inclúyela en `/etc/named.conf`, cambia la política de las zonas a `allow-update { key "actualizacion-linenes"; };` y realiza el registro desde el nodo cliente utilizando `nsupdate -k`.
1. **Reto 2: Directorios Home sobre NFSv4.2 y Booleano SELinux `use_nfs_home_dirs`**
   * En clústeres de cómputo científico y empresarial, los usuarios inician sesión por SSH en cualquier nodo y encuentran exactamente su mismo directorio `/home/<usuario>` montado por NFSv4.2. Crea una nueva exportación `/srv/nfs/homes` en el servidor, móntala en el cliente y crea un usuario sin privilegios cuyo directorio personal resida en el recurso NFS. Investiga por qué SELinux bloquea inicialmente el acceso de `sshd` a claves `~/.ssh/authorized_keys` alojadas sobre `nfs_t` y cómo habilitar de forma persistente el booleano `use_nfs_home_dirs` con `setsebool -P`.
1. **Reto 3: Convergencia con Ansible Uniendo el Cómo 03 y el Cómo 04**
   * Toma los conocimientos que adquiriste en el **Cómo 03** y escribe un Playbook de Ansible `site.yaml` con un inventario de dos grupos `[primitivas_server]` y `[primitivas_clients]` que configure de manera idempotente BIND 9, Chrony y NFSv4.2 en ambos nodos utilizando los módulos de la colección `ansible.posix`, como `ansible.posix.firewalld`, `ansible.posix.mount` y `ansible.posix.selinux`, junto con plantillas Jinja2 `.j2`. Verifica que una segunda ejecución del Playbook devuelva `changed=0` en ambos servidores.

---

### Dudas y Preguntas

Si tienes alguna duda, encuentras algún detalle técnico o quieres compartir cómo resolviste los retos, abre un issue en nuestro repositorio oficial o comenta en el hilo de la comunidad en `r/LinuxEnEspanol`:

👉 **[Reportar un issue o consulta en GitLab](https://gitlab.com/renich/cherry-servers/-/issues)**

---

## Licencia

Este documento y todo el material educativo de esta serie se distribuyen bajo los términos de la **Licencia de Documentación Libre de GNU** ([GFDL versión 1.3 o posterior](../LICENSE)). Los scripts de automatización y manifiestos de OpenTofu se licencian en paralelo bajo **GPL-3.0-or-later**.
