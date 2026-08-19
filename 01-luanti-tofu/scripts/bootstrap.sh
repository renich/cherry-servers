#!/bin/bash
set -euo pipefail

# Registro de ejecución en logs y consola
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "[+] Iniciando despliegue de Luanti (Motor Voxel FOSS) en CentOS Stream 10..."

# 1. Habilitar repositorios EPEL/CRB e instalar dependencias
dnf install -y epel-release dnf-plugins-core
/usr/bin/crb enable || true
dnf install -y \
    firewalld \
    git \
    cmake \
    gcc-c++ \
    sqlite-devel \
    zlib-devel \
    jsoncpp-devel \
    libzstd-devel \
    curl \
    tar \
    jq

# 2. Compilar el servidor dedicado headless de Luanti (64-bit nativo)
BUILD_DIR="/usr/local/src/luanti-build"
mkdir -p "$${BUILD_DIR}"
cd "$${BUILD_DIR}"

if [[ ! -d luanti ]]; then
    git clone --depth 1 https://github.com/luanti-org/luanti.git
fi

cd luanti

if [[ ! -d games/minetest_game ]]; then
    git clone --depth 1 https://github.com/minetest/minetest_game.git games/minetest_game
fi

cmake -B build \
    -DBUILD_SERVER=TRUE \
    -DBUILD_CLIENT=FALSE \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local

cmake --build build -j"$(nproc)"
cmake --install build

# 3. Instalar juego base (minetest_game) para el servidor
mkdir -p /usr/local/share/luanti/games
cp -r games/minetest_game /usr/local/share/luanti/games/

# 4. Crear usuario de sistema y estructura FHS 3.0 en /srv/luanti
useradd -r -s /sbin/nologin -d /srv/luanti -m -c "Luanti Dedicated Service" luanti || true
mkdir -p /srv/luanti/{config,worlds,games,logs}
cp -r games/minetest_game /srv/luanti/games/

# 4. Configurar el servidor en /srv/luanti/config/luanti.conf
cat <<CONFIG > /srv/luanti/config/luanti.conf
name = LinuxEnEspanol-Lab
server_name = ${SERVER_NAME}
server_description = Servidor 100% FOSS en CentOS Stream 10 desplegado con OpenTofu
server_address = 0.0.0.0
port = ${SERVER_PORT}
default_game = minetest_game
enable_damage = true
creative_mode = false
server_announce = false
max_users = 25
motd = ¡Bienvenido al servidor comunitario de r/LinuxEnEspanol! 100% FOSS en CentOS Stream 10.
CONFIG

chown -R luanti:luanti /srv/luanti
chmod 750 /srv/luanti
chmod 640 /srv/luanti/config/luanti.conf

# 5. Crear la unidad de servicio Systemd endurecida (Hardened)
cat <<SERVICE > /etc/systemd/system/luanti.service
[Unit]
Description=Luanti Dedicated Voxel Game Server
After=network.target

[Service]
Type=simple
User=luanti
Group=luanti
WorkingDirectory=/srv/luanti
ExecStart=/usr/local/bin/luantiserver --config /srv/luanti/config/luanti.conf --world /srv/luanti/worlds/midgard --gameid minetest_game
Restart=on-failure
RestartSec=5
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/srv/luanti
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

# 6. Contextos de SELinux y arranque del servicio
restorecon -Rv /srv/luanti /usr/local/bin/luantiserver || true
systemctl daemon-reload
systemctl enable --now luanti.service

# 7. Configurar Firewall para el puerto UDP de Luanti (30000)
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=${SERVER_PORT}/udp
firewall-cmd --reload

echo "[+] Servidor de Luanti desplegado con éxito en /srv/luanti y escuchando en UDP ${SERVER_PORT}."
