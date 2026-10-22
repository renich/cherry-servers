#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap (Cliente): Consumidor DNS, NTP (Chrony) y Montaje NFSv4.2
# =============================================================================
# Sistema Objetivo: CentOS Stream 10
# Seguridad:        SELinux en modo Enforcing
# Punto de Montaje: /mnt/compartido -> nfs.<dominio>:/srv/nfs/compartido
# =============================================================================

# Redirigir la salida estándar y de error al registro de user-data y a la consola
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando configuración del Nodo Cliente de Primitivas..."

# 1. Configurar el nombre de host del nodo cliente
if [[ -n "${CLIENT_NAME:-}" ]]; then
  hostnamectl set-hostname "${CLIENT_NAME}" || true
fi

DNS_DOMAIN_EFFECTIVE="${DNS_DOMAIN:-linenes.tld}"
TARGET_SERVER_IP="${SERVER_PRIVATE_IP:-${SERVER_PUBLIC_IP:-}}"

if [[ -z "${TARGET_SERVER_IP}" ]]; then
  echo "[-] Error: No se proporcionó la dirección IP del servidor de primitivas." >&2
  exit 1
fi

echo "[+] Servidor de primitivas objetivo: ${TARGET_SERVER_IP} (Dominio: ${DNS_DOMAIN_EFFECTIVE})"

# 2. Instalar utilidades de cliente DNS, Chrony, cliente NFSv4 y DNF Automatic
dnf -y install bind-utils chrony nfs-utils firewalld dnf-automatic
systemctl --now enable firewalld

# 3. Esperar a que el servidor DNS en el nodo principal responda en el puerto 53
echo "[+] Esperando disponibilidad de BIND 9 en ${TARGET_SERVER_IP}:53..."
for _ in {1..60}; do
  if dig @"${TARGET_SERVER_IP}" "ns1.${DNS_DOMAIN_EFFECTIVE}" A +short +time=2 +tries=1 | grep -qE '^[0-9]+\.'; then
    echo "[+] Servidor DNS activo y respondiendo."
    break
  fi
  sleep 3
done

# 4. Configurar resolución DNS persistente mediante NetworkManager
echo "[+] Configurando NetworkManager para utilizar ${TARGET_SERVER_IP} como servidor DNS..."
DEFAULT_DEV=$(ip -4 route show default | awk '{print $5; exit}')
PRIMARY_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="${DEFAULT_DEV}" '$NF == dev {sub(/:[^:]*$/, ""); print; exit}')
if [[ -z "${PRIMARY_CON}" ]]; then
  PRIMARY_CON=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$NF != "lo" {sub(/:[^:]*$/, ""); print; exit}')
fi
if [[ -n "${PRIMARY_CON}" ]]; then
  nmcli connection modify "${PRIMARY_CON}" ipv4.dns "${TARGET_SERVER_IP}" ipv4.dns-search "${DNS_DOMAIN_EFFECTIVE}" ipv4.ignore-auto-dns yes ipv4.dns-priority 10
  nmcli connection up "${PRIMARY_CON}" || systemctl reload NetworkManager
fi

# 5. Registrar dinámicamente los registros A y PTR de este cliente en BIND 9 (nsupdate)
CLIENT_PRIV_IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
if [[ -n "${CLIENT_PRIV_IP}" ]]; then
  IFS='.' read -r C_OCT1 C_OCT2 C_OCT3 C_OCT4 <<< "${CLIENT_PRIV_IP}"
  CLIENT_REV_ZONE="${C_OCT3}.${C_OCT2}.${C_OCT1}.in-addr.arpa"
  CLIENT_FQDN="${CLIENT_NAME:-1.primitivas.${DNS_DOMAIN_EFFECTIVE}}"

  nsupdate << EOF || echo "[!] Advertencia: Falló el registro dinámico vía nsupdate." >&2
server ${TARGET_SERVER_IP}
zone ${DNS_DOMAIN_EFFECTIVE}
update delete ${CLIENT_FQDN}. A
update add ${CLIENT_FQDN}. 86400 A ${CLIENT_PRIV_IP}
send
zone ${CLIENT_REV_ZONE}
update delete ${C_OCT4}.${CLIENT_REV_ZONE}. PTR
update add ${C_OCT4}.${CLIENT_REV_ZONE}. 86400 PTR ${CLIENT_FQDN}.
send
EOF
fi

# 6. Configurar Chrony para sincronizar el reloj contra ntp.<dominio>
echo "[+] Configurando Chrony para sincronizar tiempo con ntp.${DNS_DOMAIN_EFFECTIVE}..."
cat << EOF > /etc/chrony.conf
# =============================================================================
# Configuración de Chrony (Cliente): Sincronización contra ntp.${DNS_DOMAIN_EFFECTIVE}
# =============================================================================
server ntp.${DNS_DOMAIN_EFFECTIVE} iburst prefer
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
chronyc makestep || true

# 7. Configurar y montar el almacenamiento compartido NFSv4.2 en /mnt/compartido
echo "[+] Esperando disponibilidad del servidor NFSv4.2 en ${TARGET_SERVER_IP}:2049..."
for _ in {1..45}; do
  if timeout 2 bash -c "</dev/tcp/${TARGET_SERVER_IP}/2049" 2>/dev/null; then
    echo "[+] Servidor NFSv4.2 activo en el puerto 2049/tcp."
    break
  fi
  sleep 2
done

echo "[+] Configurando punto de montaje NFSv4.2 en /mnt/compartido..."
mkdir -p /mnt/compartido

if ! grep -q "nfs.${DNS_DOMAIN_EFFECTIVE}:/srv/nfs/compartido" /etc/fstab; then
  cat << EOF >> /etc/fstab
nfs.${DNS_DOMAIN_EFFECTIVE}:/srv/nfs/compartido  /mnt/compartido  nfs4  rw,relatime,vers=4.2,_netdev,x-systemd.automount  0  0
EOF
fi

systemctl daemon-reload
systemctl restart remote-fs.target
mount -a

# Escribir constancia de conexión desde el nodo cliente
cat << EOF > "/mnt/compartido/cliente-${CLIENT_NAME:-nodo1}.txt"
Nodo cliente ${CLIENT_NAME:-nodo1} (${CLIENT_PRIV_IP:-desconocida}) conectado vía NFSv4.2.
Fecha UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

# 8. Configurar actualizaciones automáticas de seguridad (DNF5)
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf 2>/dev/null || true
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf || true
systemctl --now enable dnf-automatic.timer

echo "[+] Configuración del Nodo Cliente de Primitivas completada con éxito."
