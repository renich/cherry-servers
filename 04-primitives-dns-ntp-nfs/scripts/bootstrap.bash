#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap (Servidor): Primitivas DNS (BIND 9), NTP (Chrony) y NFSv4.2
# =============================================================================
# Sistema Objetivo: CentOS Stream 10
# Seguridad:        SELinux en modo Enforcing + Firewalld segmentado por zonas
# Estándar FHS:     /srv/nfs/compartido (NFSv4.2) y /var/named (BIND 9)
# =============================================================================

# Redirigir la salida estándar y de error al registro de user-data y a la consola
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue del Nodo Servidor de Primitivas (DNS, NTP y NFSv4.2)..."

# 1. Configurar el nombre de host del nodo servidor
DNS_DOMAIN_EFFECTIVE="${DNS_DOMAIN:-linenes.tld}"
SERVER_NAME_EFFECTIVE="${SERVER_NAME:-0.primitivas.${DNS_DOMAIN_EFFECTIVE}}"
hostnamectl set-hostname "${SERVER_NAME_EFFECTIVE}" || true

# 2. Detectar la dirección IP privada interna (RFC 1918) o caer en la IP global primaria
SERVER_PRIV_IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
if [[ -z "${SERVER_PRIV_IP}" ]]; then
  SERVER_PRIV_IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ {print $4}' | cut -d/ -f1 | head -n1)
fi

IFS='.' read -r OCT1 OCT2 OCT3 OCT4 <<< "${SERVER_PRIV_IP}"
REV_ZONE="${OCT3}.${OCT2}.${OCT1}.in-addr.arpa"
SERVER_SHORT_HOST="${SERVER_NAME_EFFECTIVE%."${DNS_DOMAIN_EFFECTIVE}"}"
if [[ -z "${SERVER_SHORT_HOST}" ]]; then
  SERVER_SHORT_HOST="0.primitivas"
fi

echo "[+] IP de servicio detectada: ${SERVER_PRIV_IP} (Zona inversa: ${REV_ZONE})"

# 3. Instalar paquetes RPM nativos desde BaseOS y AppStream
echo "[+] Instalando BIND 9, Chrony, NFSv4, utilidades SELinux, Firewalld y DNF Automatic..."
dnf -y install bind bind-utils chrony nfs-utils policycoreutils-python-utils firewalld dnf-automatic

# 4. Configurar Firewalld ANTES de iniciar los demonios de red
#    Aislamos DNS, NTP y NFS exclusivamente en la zona 'internal' (redes privadas RFC 1918)
echo "[+] Configurando segmentación de zonas en Firewalld (zona internal vs public)..."
systemctl --now enable firewalld
firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
firewall-cmd --permanent --zone=internal --add-source=192.168.0.0/16
firewall-cmd --permanent --zone=internal --add-source=172.16.0.0/12
firewall-cmd --permanent --zone=internal --add-service=dns
firewall-cmd --permanent --zone=internal --add-service=ntp
firewall-cmd --permanent --zone=internal --add-service=nfs
firewall-cmd --reload

# 5. Configurar BIND 9 (Servidor DNS Autoritativo y Recursivo Interno)
echo "[+] Configurando BIND 9 (/etc/named.conf y archivos de zona para ${DNS_DOMAIN_EFFECTIVE})..."
cat << EOF > /etc/named.conf
// =============================================================================
// Configuración de BIND 9: DNS Autoritativo y Recursivo Interno (${DNS_DOMAIN_EFFECTIVE})
// =============================================================================

acl "red_interna" {
    127.0.0.0/8;
    ::1;
    10.0.0.0/8;
    192.168.0.0/16;
    172.16.0.0/12;
};

options {
    listen-on port 53 { 127.0.0.1; ${SERVER_PRIV_IP}; };
    listen-on-v6 port 53 { ::1; };
    directory          "/var/named";
    dump-file          "/var/named/data/cache_dump.db";
    statistics-file    "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file      "/var/named/data/named.secroots";
    recursing-file     "/var/named/data/named.recursing";

    allow-query     { "red_interna"; };
    allow-recursion { "red_interna"; };
    recursion yes;

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

zone "${DNS_DOMAIN_EFFECTIVE}" IN {
    type primary;
    file "${DNS_DOMAIN_EFFECTIVE}.zone";
    allow-update { "red_interna"; };
};

zone "${REV_ZONE}" IN {
    type primary;
    file "${DNS_DOMAIN_EFFECTIVE}.rev";
    allow-update { "red_interna"; };
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
EOF

cat << EOF > "/var/named/${DNS_DOMAIN_EFFECTIVE}.zone"
\$TTL 86400
@   IN  SOA ns1.${DNS_DOMAIN_EFFECTIVE}. admin.${DNS_DOMAIN_EFFECTIVE}. (
            2026102201  ; Serial (AAAAMMDDNN)
            3600        ; Refresh (1 hora)
            1800        ; Retry (30 minutos)
            604800      ; Expire (1 semana)
            86400 )     ; Minimum TTL (1 día)

; Servidor de nombres autoritativo
@                       IN  NS      ns1.${DNS_DOMAIN_EFFECTIVE}.

; Registros A de infraestructura
ns1                     IN  A       ${SERVER_PRIV_IP}
${SERVER_SHORT_HOST}    IN  A       ${SERVER_PRIV_IP}

; Alias canónicos de servicios (CNAME)
ntp                     IN  CNAME   ${SERVER_SHORT_HOST}.${DNS_DOMAIN_EFFECTIVE}.
nfs                     IN  CNAME   ${SERVER_SHORT_HOST}.${DNS_DOMAIN_EFFECTIVE}.
EOF

cat << EOF > "/var/named/${DNS_DOMAIN_EFFECTIVE}.rev"
\$TTL 86400
@   IN  SOA ns1.${DNS_DOMAIN_EFFECTIVE}. admin.${DNS_DOMAIN_EFFECTIVE}. (
            2026102201  ; Serial (AAAAMMDDNN)
            3600        ; Refresh (1 hora)
            1800        ; Retry (30 minutos)
            604800      ; Expire (1 semana)
            86400 )     ; Minimum TTL (1 día)

; Servidor de nombres autoritativo
@       IN  NS      ns1.${DNS_DOMAIN_EFFECTIVE}.

; Registros PTR (Resolución Inversa)
${OCT4} IN  PTR     ${SERVER_SHORT_HOST}.${DNS_DOMAIN_EFFECTIVE}.
EOF

chmod 770 /var/named
chown root:named /etc/named.conf
chmod 640 /etc/named.conf
chown named:named "/var/named/${DNS_DOMAIN_EFFECTIVE}.zone" "/var/named/${DNS_DOMAIN_EFFECTIVE}.rev"
chmod 640 "/var/named/${DNS_DOMAIN_EFFECTIVE}.zone" "/var/named/${DNS_DOMAIN_EFFECTIVE}.rev"
setsebool -P named_write_master_zones on || true
restorecon -Rv /etc/named.conf /var/named

named-checkconf -z /etc/named.conf
named-checkzone -i full "${DNS_DOMAIN_EFFECTIVE}" "/var/named/${DNS_DOMAIN_EFFECTIVE}.zone"
named-checkzone -i full "${REV_ZONE}" "/var/named/${DNS_DOMAIN_EFFECTIVE}.rev"

systemctl --now enable named.service

# 6. Configurar Chrony (Servidor NTP de Estrato Interno)
echo "[+] Configurando Chrony como servidor de tiempo NTP (/etc/chrony.conf)..."
cat << 'EOF' > /etc/chrony.conf
# =============================================================================
# Configuración de Chrony: Servidor NTP de Estrato Interno
# =============================================================================
pool 2.centos.pool.ntp.org iburst
sourcedir /run/chrony-dhcp
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony

# Permitir sincronización de clientes en la red privada interna
allow 10.0.0.0/8
allow 192.168.0.0/16
allow 172.16.0.0/12

# Mantener referencia de estrato local si se interrumpe la salida a internet
local stratum 10
EOF

restorecon -v /etc/chrony.conf
systemctl --now enable chronyd.service
systemctl restart chronyd.service

# 7. Configurar Servidor NFSv4.2 Puro bajo FHS 3.0 y SELinux Enforcing
echo "[+] Configurando almacenamiento compartido NFSv4.2 en /srv/nfs/compartido..."
mkdir -p /srv/nfs/compartido
chown root:root /srv/nfs
chmod 755 /srv/nfs
chown nobody:nobody /srv/nfs/compartido
chmod 755 /srv/nfs/compartido

# Crear archivo testigo de bienvenida en el recurso exportado
cat << EOF > /srv/nfs/compartido/bienvenida.txt
Almacenamiento compartido NFSv4.2 activo desde ${SERVER_NAME_EFFECTIVE} (${SERVER_PRIV_IP}).
SELinux en modo Enforcing con contexto nfs_t bajo FHS 3.0.
EOF
chown nobody:nobody /srv/nfs/compartido/bienvenida.txt
chmod 644 /srv/nfs/compartido/bienvenida.txt

# Registrar regla persistente de SELinux para /srv/nfs
semanage fcontext -a -t nfs_t "/srv/nfs(/.*)?" 2>/dev/null || semanage fcontext -m -t nfs_t "/srv/nfs(/.*)?"
restorecon -Rv /srv/nfs

# Forzar exclusivamente NFSv4.1 y NFSv4.2 deshabilitando protocolos legados (NFSv3)
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

cat << 'EOF' > /etc/exports
/srv/nfs/compartido 10.0.0.0/8(rw,sync,no_subtree_check,root_squash,sec=sys) 192.168.0.0/16(rw,sync,no_subtree_check,root_squash,sec=sys) 172.16.0.0/12(rw,sync,no_subtree_check,root_squash,sec=sys)
EOF

restorecon -v /etc/nfs.conf /etc/exports

systemctl --now mask rpcbind.service rpcbind.socket rpc-statd.service 2>/dev/null || true
systemctl --now enable nfs-server.service
systemctl restart nfs-server.service
exportfs -rav

# 8. Configurar actualizaciones automáticas de seguridad (DNF5)
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf 2>/dev/null || true
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf || true
systemctl --now enable dnf-automatic.timer

echo "[+] Despliegue del Nodo Servidor de Primitivas completado con éxito."
