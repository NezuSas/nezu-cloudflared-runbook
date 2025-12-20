#!/usr/bin/env bash
set -euo pipefail

# NEZU - Cloudflared tunnel runbook (Paso 13)
# Objetivo: instalar cloudflared, crear usuario/dirs, guardar token en /etc/cloudflared/cloudflared.env,
# crear servicio systemd, aplicar sysctl QUIC y arrancar el servicio.
#
# Uso:
#   export TUNNEL_TOKEN='xxx'
#   sudo -E bash scripts/setup-cloudflared.sh

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Ejecuta como root. Ejemplo: sudo -E bash $0"
  exit 1
fi

if [[ -z "${TUNNEL_TOKEN:-}" ]]; then
  echo "ERROR: Falta TUNNEL_TOKEN."
  echo "Ejemplo:"
  echo "  export TUNNEL_TOKEN='xxx'"
  echo "  sudo -E bash scripts/setup-cloudflared.sh"
  exit 1
fi

echo "[1/7] Instalando cloudflared..."
apt-get update
apt-get install -y cloudflared

echo "[2/7] Unificando binario..."
rm -f /usr/local/bin/cloudflared || true
ln -sf /usr/bin/cloudflared /usr/local/bin/cloudflared || true
hash -r || true

echo "[3/7] Creando usuario y directorio..."
getent passwd cloudflared >/dev/null || useradd -r -s /usr/sbin/nologin -U cloudflared
install -d -m 0750 -o root -g cloudflared /etc/cloudflared

echo "[4/7] Creando env con token del túnel..."
umask 077
cat > /etc/cloudflared/cloudflared.env <<EOF
TUNNEL_TOKEN=${TUNNEL_TOKEN}
EOF
chown root:cloudflared /etc/cloudflared/cloudflared.env
chmod 0640 /etc/cloudflared/cloudflared.env

echo "[5/7] Creando servicio systemd..."
cat > /etc/systemd/system/cloudflared.service <<'EOF'
[Unit]
Description=cloudflared (Cloudflare Tunnel)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=/etc/cloudflared/cloudflared.env
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel run --token ${TUNNEL_TOKEN}
Restart=on-failure
RestartSec=5s
TimeoutStartSec=30
User=cloudflared
Group=cloudflared
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudflared

echo "[6/7] Aplicando sysctl QUIC recomendado..."
cat > /etc/sysctl.d/99-cloudflared-quic.conf <<'EOF'
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.rmem_default=2621440
net.core.wmem_default=2621440
EOF

sysctl --system >/dev/null
systemctl restart cloudflared

echo "[7/7] Validando estado y logs..."
systemctl status cloudflared --no-pager || true
journalctl -u cloudflared -n 50 --no-pager || true

echo "OK: cloudflared instalado y corriendo."
