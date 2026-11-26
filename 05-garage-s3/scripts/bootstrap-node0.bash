#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap (Nodo 0): Garage S3 (Podman Quadlet) + Caddy TLS
# =============================================================================
# Sistema Objetivo: CentOS Stream 10
# Seguridad:        SELinux Enforcing + Firewalld (internal vs public)
# Estándar FHS:     /srv/garage/{meta,data} y /etc/garage/garage.toml
# Puerta de Enlace: Caddy (EPEL 10) con Let's Encrypt vía sslip.io
# =============================================================================

exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue de Nodo 0 del clúster Garage S3..."

# 1. Configurar nombre de host e identificar direcciones IP privada (VLAN) y pública (WAN)
hostnamectl set-hostname "${NODE_NAME}" || true

priv_ip=$(ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
if [[ -z "$priv_ip" ]]; then
  echo "[-] Error: No se detectó dirección IPv4 privada RFC 1918 en la VLAN interna." >&2
  exit 1
fi

public_ip=$(curl -fs4 --connect-timeout 5 --max-time 10 https://icanhazip.com || ip -4 -o addr show scope global | awk '$2 !~ /^(podman|veth|br-|cni)/ && $4 !~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ {print $4}' | cut -d/ -f1 | head -n1)
if [[ -z "$public_ip" ]]; then
  echo "[-] Error: No se pudo determinar la dirección IPv4 pública del Nodo 0." >&2
  exit 1
fi

echo "[+] Nodo 0 (${NODE_NAME}): IP privada=$priv_ip | IP pública=$public_ip"

# 2. Habilitar EPEL 10, CRB e instalar Podman, Caddy, Firewalld y utilidades
dnf -y install epel-release
/usr/bin/crb enable || true
dnf -y install podman caddy firewalld jq curl dnf-automatic policycoreutils-python-utils

# 3. Configurar Firewalld antes de arrancar contenedores o proxy inverso
#    Puerto RPC/Admin/S3 restringido a RFC 1918 (internal); WAN (public) solo HTTP/HTTPS + SSH.
systemctl --now enable firewalld
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
firewall-cmd --permanent --zone=internal --add-source=192.168.0.0/16
firewall-cmd --permanent --zone=internal --add-source=172.16.0.0/12
firewall-cmd --permanent --zone=internal --add-port=3900/tcp
firewall-cmd --permanent --zone=internal --add-port=3901/tcp
firewall-cmd --permanent --zone=internal --add-port=3902/tcp
firewall-cmd --permanent --zone=internal --add-port=3903/tcp
firewall-cmd --reload

# 4. Crear estructura FHS 3.0 y archivo de configuración /etc/garage/garage.toml
mkdir -p /srv/garage/{meta,data} /etc/garage /etc/containers/systemd /etc/caddy /var/log/caddy
chmod 750 /srv/garage /srv/garage/meta /srv/garage/data /etc/garage

printf '%s\n' "$public_ip" > /etc/garage/public-ip
chmod 644 /etc/garage/public-ip

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

# 5. Declarar Podman Quadlet para Garage (enlazado solo a loopback e IP privada VLAN)
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

# 6. Configurar Caddy inicial con TLS automático en sslip.io y política SELinux Enforcing
cat << EOF > /etc/caddy/Caddyfile
s3.$public_ip.sslip.io {
    reverse_proxy 127.0.0.1:3900

    log {
        output file /var/log/caddy/garage-s3.access.log
        format json
    }
}

web.$public_ip.sslip.io {
    reverse_proxy 127.0.0.1:3902 {
        header_up Host sitio.web.linenes.tld
    }

    log {
        output file /var/log/caddy/garage-web.access.log
        format json
    }
}
EOF

caddy fmt --overwrite /etc/caddy/Caddyfile
chown -R caddy:caddy /etc/caddy /var/log/caddy
chmod 750 /var/log/caddy
chmod 640 /etc/caddy/Caddyfile
semanage fcontext -a -t httpd_log_t '/var/log/caddy(/.*)?' 2>/dev/null || semanage fcontext -m -t httpd_log_t '/var/log/caddy(/.*)?' || true
setsebool -P httpd_can_network_connect 1
restorecon -Rv /etc/caddy /var/log/caddy
runuser -u caddy -- caddy validate --config /etc/caddy/Caddyfile
restorecon -Rv /etc/caddy /var/log/caddy
systemctl --now enable caddy.service

# 7. Script y unidad oneshot asíncrona para inicializar layout de 3 zonas y balanceo en Caddy
cat << 'INIT_EOF' > /usr/local/sbin/garage-cluster-init.bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

public_ip=$(cat /etc/garage/public-ip)
status_json=""

echo "[+] Esperando a que los 3 nodos de Garage estén conectados..."
for _ in $(seq 1 120); do
  if status_json=$(podman exec garage /garage json-api GetClusterStatus 2>/dev/null); then
    up_count=$(printf '%s\n' "$status_json" | jq '[.nodes[] | select(.isUp == true and .addr != null)] | length')
    if [[ "$up_count" -ge 3 ]]; then
      echo "[+] Malla completa detectada ($up_count nodos activos)."
      break
    fi
  fi
  sleep 5
done

up_count=$(printf '%s\n' "$status_json" | jq '[.nodes[] | select(.isUp == true and .addr != null)] | length')
if [[ "$up_count" -lt 3 ]]; then
  echo "[-] Tiempo agotado esperando 3 nodos activos en Garage." >&2
  exit 1
fi

layout_ver=$(printf '%s\n' "$status_json" | jq -r '.layoutVersion')
if [[ "$layout_ver" -eq 0 ]]; then
  zone_num=1
  while IFS=$'\t' read -r nid nhost; do
    zone="z$zone_num"
    podman exec garage /garage layout assign "$nid" -z "$zone" -c 10G -t "$nhost"
    zone_num=$((zone_num + 1))
  done < <(printf '%s\n' "$status_json" | jq -r '[.nodes[] | select(.isUp == true)] | sort_by(.hostname)[] | [.id, (.hostname // .id[:8])] | @tsv')

  podman exec garage /garage layout apply --version 1
  echo "[+] Topología de clúster v1 aplicada en zonas z1, z2 y z3."
fi

if ! podman exec garage /garage bucket info sitio >/dev/null 2>&1; then
  podman exec garage /garage bucket create sitio
fi
podman exec garage /garage bucket website --allow sitio

if [[ ! -f /root/garage-credentials.txt ]]; then
  key_json=$(podman exec garage /garage json-api CreateKey '{"name":"lab-key"}')
  access_key=$(printf '%s\n' "$key_json" | jq -r '.accessKeyId')
  secret_key=$(printf '%s\n' "$key_json" | jq -r '.secretAccessKey')
  podman exec garage /garage bucket allow --read --write --owner sitio --key "$access_key"

  umask 077
  cat << CRED_EOF > /root/garage-credentials.txt
S3_ENDPOINT=https://s3.$public_ip.sslip.io
WEB_ENDPOINT=https://web.$public_ip.sslip.io
AWS_DEFAULT_REGION=garage
AWS_ACCESS_KEY_ID=$access_key
AWS_SECRET_ACCESS_KEY=$secret_key
BUCKET_NAME=sitio
CRED_EOF
  chmod 600 /root/garage-credentials.txt
  umask 022
fi

s3_backends=""
web_backends=""
while IFS= read -r peer_ip; do
  if [[ -n "$s3_backends" ]]; then
    s3_backends+=" "
    web_backends+=" "
  fi
  s3_backends+="$peer_ip:3900"
  web_backends+="$peer_ip:3902"
done < <(printf '%s\n' "$status_json" | jq -r '[.nodes[] | select(.isUp == true and .addr != null)] | sort_by(.hostname)[] | (.addr | split(":")[0])')

cat << CADDY_EOF > /etc/caddy/Caddyfile
s3.$public_ip.sslip.io {
    reverse_proxy $s3_backends {
        fail_duration 10s
        lb_try_duration 5s
    }

    log {
        output file /var/log/caddy/garage-s3.access.log
        format json
    }
}

web.$public_ip.sslip.io {
    reverse_proxy $web_backends {
        fail_duration 10s
        lb_try_duration 5s
        header_up Host sitio.web.linenes.tld
    }

    log {
        output file /var/log/caddy/garage-web.access.log
        format json
    }
}
CADDY_EOF

caddy fmt --overwrite /etc/caddy/Caddyfile
chown caddy:caddy /etc/caddy/Caddyfile
chmod 640 /etc/caddy/Caddyfile
restorecon -v /etc/caddy/Caddyfile
runuser -u caddy -- caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy.service
echo "[+] Clúster Garage S3 y proxy Caddy multi-nodo operativos."
INIT_EOF

chmod 750 /usr/local/sbin/garage-cluster-init.bash

cat << 'UNIT_EOF' > /etc/systemd/system/garage-cluster-init.service
[Unit]
Description=Inicialización automática del clúster Garage S3 de 3 nodos
After=garage.service caddy.service
Wants=garage.service caddy.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=HOME=/root
ExecStart=/usr/local/sbin/garage-cluster-init.bash

[Install]
WantedBy=multi-user.target
UNIT_EOF

chmod 644 /etc/systemd/system/garage-cluster-init.service
systemctl daemon-reload
systemctl enable garage-cluster-init.service
systemctl --no-block start garage-cluster-init.service

# 8. Actualizaciones automáticas de seguridad en DNF5 (%ghost guard)
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf 2>/dev/null || true
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf || true
systemctl --now enable dnf-automatic.timer

echo "[+] Bootstrap de Nodo 0 completado; inicialización de clúster en curso."
