#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap del Nodo 1: Cliente DNS, NTP con Chrony y Montaje NFSv4.2
# =============================================================================
# Sistema Objetivo: CentOS Stream 10
# Seguridad:        SELinux en modo Enforcing y Firewalld activo
# Punto de Montaje: /mnt/compartido -> nfs.<dominio>:/srv/nfs/compartido
# =============================================================================

# Redirigir la salida estándar y de error al registro de user-data y a la consola
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando configuración del Nodo 1, cliente de primitivas..."

# 1. Configurar el nombre de host y validar las direcciones IP privadas RFC 1918
domain="${DNS_DOMAIN}"
if [[ -z "$domain" ]]; then
  domain="linenes.tld"
fi

node_fqdn="${CLIENT_NAME}"
if [[ -z "$node_fqdn" ]]; then
  node_fqdn="1.primitivas.$domain"
fi
hostnamectl set-hostname "$node_fqdn" || true

srv_priv_ip="${SERVER_PRIVATE_IP}"
srv_pub_ip="${SERVER_PUBLIC_IP}"

if [[ -z "$srv_priv_ip" ]] || ! printf '%s\n' "$srv_priv_ip" | grep -qE '^(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[0-1])(\.[0-9]{1,3}){2})$'; then
  echo "[-] Error: Se requiere una dirección IPv4 privada RFC 1918 del Nodo 0; recibida='$srv_priv_ip', pública='$srv_pub_ip'." >&2
  exit 1
fi

client_priv_ip=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
if [[ -z "$client_priv_ip" ]]; then
  echo "[-] Error: No se detectó una dirección IPv4 privada RFC 1918 en la VLAN interna del Nodo 1." >&2
  exit 1
fi

echo "[+] Nodo 0 objetivo: IP privada=$srv_priv_ip | IP pública=$srv_pub_ip | Dominio=$domain"
echo "[+] Nodo 1 local: nombre=$node_fqdn | IP privada=$client_priv_ip"

# 2. Instalar utilidades de cliente DNS, Chrony, cliente NFSv4, Firewalld y DNF Automatic
dnf -y install bind-utils chrony nfs-utils firewalld dnf-automatic
systemctl --now enable firewalld

# 3. Esperar a que el servidor DNS en el Nodo 0 responda en el puerto 53
echo "[+] Esperando disponibilidad de BIND 9 en $srv_priv_ip:53..."
dns_ready=false
for _ in $(seq 1 60); do
  if dig @"$srv_priv_ip" "ns1.$domain" A +short +time=2 +tries=1 | grep -qE '^[0-9]+\.'; then
    echo "[+] Servidor DNS activo y respondiendo."
    dns_ready=true
    break
  fi
  sleep 3
done
if [[ "$dns_ready" != "true" ]]; then
  echo "[-] Error: Tiempo agotado esperando respuesta DNS de BIND 9 en $srv_priv_ip:53." >&2
  exit 1
fi

# 4. Configurar resolución DNS persistente mediante NetworkManager
echo "[+] Configurando NetworkManager para utilizar $srv_priv_ip como servidor DNS..."
default_dev=$(ip -4 route show default | awk '{print $5; exit}')
primary_con=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$default_dev" '$NF == dev {sub(/:[^:]*$/, ""); print; exit}')
if [[ -z "$primary_con" ]]; then
  primary_con=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: '$NF != "lo" {sub(/:[^:]*$/, ""); print; exit}')
fi
if [[ -z "$primary_con" ]]; then
  echo "[-] Error: No se encontró una conexión activa en NetworkManager para configurar DNS." >&2
  exit 1
fi
nmcli connection modify "$primary_con" ipv4.dns "$srv_priv_ip" ipv4.dns-search "$domain" ipv4.ignore-auto-dns yes ipv4.dns-priority 10
nmcli connection up "$primary_con" || systemctl reload NetworkManager

# 5. Registrar dinámicamente los registros A y PTR de este cliente en BIND 9 vía nsupdate
IFS='.' read -r c_oct1 c_oct2 c_oct3 c_oct4 <<< "$client_priv_ip"
client_rev_zone="$c_oct3.$c_oct2.$c_oct1.in-addr.arpa"

nsupdate << EOF || echo "[!] Advertencia: Falló el registro dinámico vía nsupdate." >&2
server $srv_priv_ip
zone $domain
update delete $node_fqdn. A
update add $node_fqdn. 86400 A $client_priv_ip
send
zone $client_rev_zone
update delete $c_oct4.$client_rev_zone. PTR
update add $c_oct4.$client_rev_zone. 86400 PTR $node_fqdn.
send
EOF

# 6. Configurar Chrony para sincronizar el reloj contra ntp.<dominio>
echo "[+] Configurando Chrony para sincronizar tiempo con ntp.$domain..."
cat << EOF > /etc/chrony.conf
# =============================================================================
# Configuración de Chrony en cliente: sincronización contra ntp.$domain
# =============================================================================
server ntp.$domain iburst prefer
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

# 7. Esperar al servidor NFSv4.2 y montar el recurso compartido en /mnt/compartido
echo "[+] Esperando disponibilidad del servidor NFSv4.2 en $srv_priv_ip:2049..."
nfs_ready=false
for _ in $(seq 1 45); do
  if timeout 2 bash -c "</dev/tcp/$srv_priv_ip/2049" 2>/dev/null; then
    echo "[+] Servidor NFSv4.2 activo en el puerto 2049/tcp."
    nfs_ready=true
    break
  fi
  sleep 2
done
if [[ "$nfs_ready" != "true" ]]; then
  echo "[-] Error: Tiempo agotado esperando el servidor NFSv4.2 en $srv_priv_ip:2049." >&2
  exit 1
fi

echo "[+] Configurando punto de montaje NFSv4.2 en /mnt/compartido..."
mkdir -p /mnt/compartido

if ! grep -Fq "nfs.$domain:/srv/nfs/compartido" /etc/fstab; then
  cat << EOF >> /etc/fstab
nfs.$domain:/srv/nfs/compartido  /mnt/compartido  nfs4  rw,relatime,vers=4.2,_netdev,x-systemd.automount  0  0
EOF
fi

systemctl daemon-reload
systemctl restart remote-fs.target
mount -a

# Escribir constancia de conexión desde el nodo cliente
cat << EOF > "/mnt/compartido/cliente-$node_fqdn.txt"
Nodo cliente $node_fqdn ($client_priv_ip) conectado vía NFSv4.2.
Fecha UTC: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

# 8. Configurar actualizaciones automáticas del sistema en DNF5
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf 2>/dev/null || true
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf || true
systemctl --now enable dnf-automatic.timer

echo "[+] Configuración del Nodo 1 completada con éxito."
