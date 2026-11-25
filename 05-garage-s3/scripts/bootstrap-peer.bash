#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap (Nodos 1 y 2): Almacenamiento Garage S3 (Podman Quadlet)
# =============================================================================
# Sistema Objetivo: CentOS Stream 10
# Seguridad:        SELinux Enforcing + Firewalld (solo internal en puertos Garage)
# Estándar FHS:     /srv/garage/{meta,data} y /etc/garage/garage.toml
# =============================================================================

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue de nodo par de almacenamiento Garage S3..."

# 1. Configurar nombre de host e inspeccionar la dirección IP privada en la VLAN interna
hostnamectl set-hostname "${NODE_NAME}" || true

node0_ip="${NODE0_PRIVATE_IP}"
if [[ -z "$node0_ip" ]]; then
  echo "[-] Error: No se recibió la IP privada del Nodo 0." >&2
  exit 1
fi

priv_ip=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
if [[ -z "$priv_ip" ]]; then
  echo "[-] Error: No se detectó dirección IPv4 privada RFC 1918 en la VLAN interna." >&2
  exit 1
fi

echo "[+] Nodo par (${NODE_NAME}): IP privada=$priv_ip | Nodo 0=$node0_ip"

# 2. Habilitar EPEL 10 e instalar Podman, Firewalld, jq, curl y dnf-automatic
dnf -y install epel-release
/usr/bin/crb enable || true
dnf -y install podman firewalld jq curl dnf-automatic

# 3. Configurar Firewalld ANTES de iniciar contenedores
#    La zona public permanece cerrada a solo SSH; puertos Garage estrictamente en internal.
systemctl --now enable firewalld
firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
firewall-cmd --permanent --zone=internal --add-source=192.168.0.0/16
firewall-cmd --permanent --zone=internal --add-source=172.16.0.0/12
firewall-cmd --permanent --zone=internal --add-port=3900/tcp
firewall-cmd --permanent --zone=internal --add-port=3901/tcp
firewall-cmd --permanent --zone=internal --add-port=3902/tcp
firewall-cmd --permanent --zone=internal --add-port=3903/tcp
firewall-cmd --reload

# 4. Crear estructura FHS 3.0 y configuración /etc/garage/garage.toml
mkdir -p /srv/garage/{meta,data} /etc/garage /etc/containers/systemd
chmod 750 /srv/garage /srv/garage/meta /srv/garage/data /etc/garage

umask 027
cat << EOF > /etc/garage/garage.toml
# =============================================================================
# Configuración de Garage S3 (${NODE_NAME})
# =============================================================================
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"

replication_factor = 3
consistency_mode = "consistent"

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "$priv_ip:3901"
rpc_secret = "${RPC_SECRET}"
allow_world_readable_secrets = false

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.linenes.tld"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.linenes.tld"
index = "index.html"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "${ADMIN_TOKEN}"
EOF
umask 022
chown root:root /etc/garage/garage.toml
chmod 640 /etc/garage/garage.toml

# 5. Declarar Podman Quadlet para Garage e iniciar servicio
cat << EOF > /etc/containers/systemd/garage.container
[Unit]
Description=Garage Distributed S3 Storage (${GARAGE_VERSION})
Documentation=https://garagehq.deuxfleurs.fr/
After=network-online.target firewalld.service
Wants=network-online.target

[Container]
Image=docker.io/dxflrs/garage:${GARAGE_VERSION}
ContainerName=garage
HostName=${NODE_NAME}
PublishPort=127.0.0.1:3900:3900
PublishPort=$priv_ip:3900:3900
PublishPort=127.0.0.1:3901:3901
PublishPort=$priv_ip:3901:3901
PublishPort=127.0.0.1:3902:3902
PublishPort=$priv_ip:3902:3902
PublishPort=127.0.0.1:3903:3903
PublishPort=$priv_ip:3903:3903
Volume=/srv/garage/meta:/var/lib/garage/meta:Z
Volume=/srv/garage/data:/var/lib/garage/data:Z
Volume=/etc/garage/garage.toml:/etc/garage.toml:ro,Z
Environment=RUST_LOG=garage=info
AutoUpdate=registry

[Service]
Restart=on-failure
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target default.target
EOF

chmod 644 /etc/containers/systemd/garage.container
systemctl daemon-reload
systemctl start garage.service
systemctl --now enable podman-auto-update.timer

# 6. Consultar Admin API del Nodo 0 en la VLAN privada y unir este nodo al clúster
echo "[+] Consultando ID de Nodo 0 en http://$node0_ip:3903/v2/GetClusterStatus..."
node0_id=""
for _ in $(seq 1 60); do
  if resp=$(curl -fsS --connect-timeout 5 --max-time 10 -H "Authorization: Bearer ${ADMIN_TOKEN}" "http://$node0_ip:3903/v2/GetClusterStatus" 2>/dev/null); then
    node0_id=$(printf '%s\n' "$resp" | jq -r --arg ip "$node0_ip" '.nodes[] | select(.isUp == true and ((.addr // "") | startswith($ip + ":"))) | .id' | head -n1)
    if [[ -n "$node0_id" && "$node0_id" != "null" ]]; then
      break
    fi
  fi
  sleep 5
done

if [[ -z "$node0_id" || "$node0_id" == "null" ]]; then
  echo "[-] Error: No se pudo obtener el ID del Nodo 0 desde la VLAN privada." >&2
  exit 1
fi

podman exec garage /garage node connect "$node0_id@$node0_ip:3901"
echo "[+] Conectado exitosamente al Nodo 0 ($node0_id)."

# 7. Actualizaciones automáticas de seguridad en DNF5 (%ghost guard)
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf 2>/dev/null || true
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf || true
systemctl --now enable dnf-automatic.timer

echo "[+] Bootstrap del nodo par ${NODE_NAME} completado."
