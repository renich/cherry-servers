#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap: Caddy (RPM) + Vaultwarden (Podman Quadlet)
# =============================================================================
# Sistema Objetivo: CentOS Stream 10
# Seguridad:        SELinux en modo Enforcing
# Estándar FHS:     /srv/vaultwarden/data
# Proxy Inverso:    Caddy v2 con soporte TLS y dominio virtual
# =============================================================================

# Redirigir la salida estándar y de error al registro de user-data y a la consola
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue de Caddy + Vaultwarden en CentOS Stream 10..."

# 1. Habilitar repositorios EPEL 10, CRB y el repositorio COPR oficial de Caddy
echo "[+] Configurando repositorios EPEL 10, CRB y COPR (@caddy/caddy)..."
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable || true
dnf -y copr enable @caddy/caddy

# 2. Instalar Caddy, Podman y herramientas auxiliares
echo "[+] Instalando paquetes RPM: caddy, podman, firewalld, curl y jq..."
dnf -y install caddy podman firewalld curl jq

# 3. Crear estructura de datos persistente bajo FHS 3.0
echo "[+] Creando estructura de datos en /srv/vaultwarden/data..."
mkdir -p /srv/vaultwarden/data
chmod 750 /srv/vaultwarden /srv/vaultwarden/data

# 4. Declarar el contenedor de Vaultwarden mediante Podman Quadlet
echo "[+] Configurando archivo Podman Quadlet /etc/containers/systemd/vaultwarden.container..."
mkdir -p /etc/containers/systemd
cat << 'EOF' > /etc/containers/systemd/vaultwarden.container
[Unit]
Description=Vaultwarden Password Manager (Podman Quadlet)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network-online.target firewalld.service

[Container]
Image=docker.io/vaultwarden/server:latest
ContainerName=vaultwarden
PublishPort=127.0.0.1:8080:80
Volume=/srv/vaultwarden/data:/data:Z
Environment=SIGNUPS_ALLOWED=true
Environment=WEBSOCKET_ENABLED=true
AutoUpdate=registry

[Install]
WantedBy=multi-user.target default.target
EOF

chmod 644 /etc/containers/systemd/vaultwarden.container

# 5. Cargar generador Quadlet y arrancar el servicio en Systemd
echo "[+] Recargando Systemd y arrancando vaultwarden.service..."
systemctl daemon-reload
systemctl enable --now vaultwarden.service

# 6. Configurar Caddyfile con FQDN y proxy inverso
echo "[+] Generando configuración de Caddy (/etc/caddy/Caddyfile)..."
mkdir -p /etc/caddy /var/log/caddy

cat << EOF > /etc/caddy/Caddyfile
# =============================================================================
# Configuración de Caddy para Vaultwarden en CentOS Stream 10
# =============================================================================

{
    admin off
}

${VAULT_DOMAIN} {
    ${TLS_DIRECTIVE}

    # Proxy inverso al contenedor local en loopback
    reverse_proxy 127.0.0.1:8080 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    log {
        output file /var/log/caddy/vaultwarden.access.log
        format json
    }
}
EOF

chown -R caddy:caddy /etc/caddy /var/log/caddy
chmod 640 /etc/caddy/Caddyfile

# 7. Configuración estricta de SELinux (Modo Enforcing)
echo "[+] Aplicando políticas de SELinux..."
# Permitir que el dominio de Caddy (httpd_t) inicie conexiones TCP hacia localhost
setsebool -P httpd_can_network_connect 1

# Restaurar etiquetas de contexto en FHS y configuraciones
restorecon -Rv /srv/vaultwarden /etc/caddy /var/log/caddy || true

# 8. Arrancar e iniciar el servicio Caddy
echo "[+] Habilitando e iniciando servicio caddy.service..."
systemctl enable --now caddy.service

# 9. Configuración de Firewalld para HTTP (80/tcp) y HTTPS (443/tcp)
echo "[+] Configurando reglas de firewall (HTTP y HTTPS)..."
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

echo "[+] Despliegue completado con éxito. Vaultwarden disponible bajo https://${VAULT_DOMAIN}"
