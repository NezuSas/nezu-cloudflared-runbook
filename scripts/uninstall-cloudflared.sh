#!/usr/bin/env bash
set -euo pipefail

# NEZU - Cloudflare Tunnel en una MiniPC: desinstalación
# Deshace lo que hizo scripts/setup-cloudflared.sh: detiene y elimina el servicio, borra el token,
# retira el ajuste de sysctl y, si se pide, desinstala el paquete.
#
# Uso:
#   sudo bash scripts/uninstall-cloudflared.sh            # conserva el paquete cloudflared
#   sudo bash scripts/uninstall-cloudflared.sh --purge    # además desinstala el paquete y borra el usuario

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Ejecuta como root. Ejemplo: sudo bash $0"
  exit 1
fi

purge=false
[[ "${1:-}" != "--purge" ]] || purge=true

echo "[1/4] Deteniendo y deshabilitando el servicio..."
systemctl disable --now cloudflared 2>/dev/null || true
rm -f /etc/systemd/system/cloudflared.service
systemctl daemon-reload

echo "[2/4] Borrando el token y la configuración..."
if [[ -f /etc/cloudflared/cloudflared.env ]]; then
  shred -u /etc/cloudflared/cloudflared.env 2>/dev/null || rm -f /etc/cloudflared/cloudflared.env
fi
rmdir /etc/cloudflared 2>/dev/null || true

echo "[3/4] Retirando el ajuste de sysctl para QUIC..."
rm -f /etc/sysctl.d/99-cloudflared-quic.conf
sysctl --system >/dev/null

if [[ "$purge" == true ]]; then
  echo "[4/4] Desinstalando el paquete y el usuario..."
  apt-get remove -y cloudflared >/dev/null 2>&1 || true
  rm -f /usr/local/bin/cloudflared
  userdel cloudflared 2>/dev/null || true
else
  echo "[4/4] Paquete conservado (usa --purge para desinstalarlo)."
fi

echo "OK: el túnel ya no corre en este equipo. Recuerda borrar o rotar el conector en el panel de Cloudflare Zero Trust."
