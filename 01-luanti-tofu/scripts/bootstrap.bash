#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script de Arranque y Despliegue de Luanti en CentOS Stream 10
# =============================================================================
# Repositorio RPM: Fedora COPR, dherrera/minetest para EPEL 10
# Estándar FHS:    /var/lib/minetest y /etc/minetest
# Servicio:        minetest@default.service en Systemd
# =============================================================================

# Redirigir la salida estándar y de error al registro de user-data y a la consola
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

printf '[+] Iniciando despliegue de Luanti en CentOS Stream 10...\n'

# 1. Configurar el nombre de host del servidor
hostnamectl set-hostname "${SERVER_NAME}" || true

# 2. Habilitar repositorios EPEL 10, CRB y el repositorio COPR de la comunidad
printf '[+] Configurando repositorios EPEL 10, CRB y COPR dherrera/minetest...\n'
dnf -y install epel-release dnf-plugins-core
/usr/bin/crb enable || true
dnf -y copr enable dherrera/minetest

# 3. Instalar el paquete RPM del servidor dedicado, cortafuegos y actualizaciones automáticas
printf '[+] Instalando minetest-server, firewalld y dnf-automatic...\n'
dnf -y install minetest-server firewalld dnf-automatic

# 4. Asegurar estructura de datos y permisos bajo FHS 3.0
printf '[+] Configurando directorios y permisos en /var/lib/minetest y /etc/minetest...\n'
mkdir -p /var/lib/minetest/{default,.minetest/games} /etc/minetest /etc/sysconfig/minetest
chown -R minetest:minetest /var/lib/minetest /etc/minetest
chmod 750 /var/lib/minetest /etc/minetest

# 5. Configurar el servidor en /etc/minetest/default.conf
#    OpenTofu ya sustituyó SERVER_NAME y SERVER_PORT mediante templatefile()
printf '[+] Escribiendo configuración en /etc/minetest/default.conf...\n'
cat << 'EOF' > /etc/minetest/default.conf
# Cuenta administradora del servidor; personalízala antes de compartir tu IP pública
name = tu_usuario_admin
server_name = ${SERVER_NAME}
server_description = Servidor 100% FOSS en CentOS Stream 10 desplegado con OpenTofu y COPR
port = ${SERVER_PORT}
default_game = minetest_game
enable_damage = true
creative_mode = false
server_announce = false
max_users = 25
motd = ¡Bienvenido al servidor comunitario de Luanti! Empaquetado en COPR y desplegado con OpenTofu.
EOF

chown minetest:minetest /etc/minetest/default.conf
chmod 640 /etc/minetest/default.conf

# 6. Sincronizar PORT en /etc/sysconfig/minetest/default.conf para minetest@.service
printf '[+] Configurando puerto UDP %s en /etc/sysconfig/minetest/default.conf...\n' "${SERVER_PORT}"
sysconfig_file="/etc/sysconfig/minetest/default.conf"
if [[ -f "$sysconfig_file" ]]; then
  [[ -z "$(tail -c 1 "$sysconfig_file")" ]] || printf '\n' >> "$sysconfig_file"
  if grep -q '^PORT=' "$sysconfig_file"; then
    sed -i "s/^PORT=.*/PORT=${SERVER_PORT}/" "$sysconfig_file"
  else
    printf 'PORT=%s\n' "${SERVER_PORT}" >> "$sysconfig_file"
  fi
  if ! grep -q '^GAMEID=' "$sysconfig_file"; then
    printf 'GAMEID=minetest_game\n' >> "$sysconfig_file"
  fi
else
  cat << 'EOF' > "$sysconfig_file"
PORT=${SERVER_PORT}
GAMEID=minetest_game
EOF
fi
chmod 644 "$sysconfig_file"

# 7. Aplicar contextos SELinux y abrir el puerto UDP en firewalld antes de iniciar el servicio
printf '[+] Aplicando contextos de SELinux y abriendo puerto UDP %s en firewalld...\n' "${SERVER_PORT}"
restorecon -Rv /var/lib/minetest /etc/minetest /usr/bin/minetestserver
systemctl --now enable firewalld
firewall-cmd --permanent --add-port="${SERVER_PORT}/udp"
firewall-cmd --reload

# 8. Habilitar e iniciar la instancia de Luanti en Systemd
printf '[+] Habilitando e iniciando servicio minetest@default.service...\n'
systemctl daemon-reload
systemctl --now enable minetest@default.service

# 9. Configurar actualizaciones automáticas en CentOS Stream 10 con guarda %ghost de DNF5
printf '[+] Configurando actualizaciones automáticas con dnf-automatic...\n'
[[ -f /etc/dnf/automatic.conf ]] || cp /usr/share/dnf5/dnf5-plugins/automatic.conf /etc/dnf/automatic.conf
sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl --now enable dnf-automatic.timer

printf '[+] Despliegue completado con éxito. Servidor escuchando en UDP %s.\n' "${SERVER_PORT}"
