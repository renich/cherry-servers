#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Bootstrap y Despliegue de Luanti (Minetest) en CentOS Stream 10
# =============================================================================
# Repositorio RPM: Fedora COPR (dherrera/minetest para EPEL 10)
# Estándar FHS:    /var/lib/minetest
# Servicio:        minetest@default.service (Systemd)
# =============================================================================

# Redirigir la salida estándar y de error al registro de user-data y a la consola
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue de Luanti (Minetest Server) en CentOS Stream 10..."

# 1. Habilitar repositorios EPEL 10, CRB y el repositorio COPR de la comunidad
echo "[+] Configurando repositorios EPEL, CRB y COPR (dherrera/minetest)..."
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable || true
dnf -y copr enable dherrera/minetest

# 2. Instalar el paquete RPM del servidor y utilerías
echo "[+] Instalando paquete RPM de minetest-server..."
dnf -y install minetest-server firewalld jq curl

# 3. Asegurar propiedad y permisos de directorios de datos
echo "[+] Configurando permisos en /var/lib/minetest..."
mkdir -p /var/lib/minetest/{default,.minetest/games}
chown -R minetest:minetest /var/lib/minetest /etc/minetest
chmod 750 /var/lib/minetest

# 4. Configurar el servidor en /etc/minetest/default.conf
echo "[+] Escribiendo archivo de configuración /etc/minetest/default.conf..."
cat <<CONFIG > /etc/minetest/default.conf
name = LinuxEnEspanol-Lab
server_name = ${SERVER_NAME}
server_description = Servidor 100% FOSS en CentOS Stream 10 desplegado con OpenTofu y COPR
server_address = 0.0.0.0
port = ${SERVER_PORT}
default_game = minetest_game
enable_damage = true
creative_mode = false
server_announce = false
max_users = 25
motd = ¡Bienvenido al servidor comunitario de Luanti! Empaquetado en COPR y desplegado con OpenTofu.
CONFIG

chown minetest:minetest /etc/minetest/default.conf
chmod 640 /etc/minetest/default.conf

# 5. Configurar e iniciar el servicio en Systemd
echo "[+] Habilitando e iniciando servicio minetest@default.service..."
restorecon -Rv /var/lib/minetest /etc/minetest /usr/bin/minetestserver || true
systemctl daemon-reload
systemctl enable --now minetest@default.service

# 6. Configurar Firewalld para el puerto UDP del servidor
echo "[+] Configurando reglas de firewall (UDP ${SERVER_PORT})..."
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=${SERVER_PORT}/udp
firewall-cmd --reload

echo "[+] Despliegue completado con éxito. Servidor escuchando en UDP ${SERVER_PORT}."
