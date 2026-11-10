#!/usr/bin/env bash
set -euo pipefail

# NEZU - Cloudflare Tunnel en una MiniPC: desinstalación
#
# Deshace lo que hizo scripts/setup-cloudflared.sh: detiene y elimina el servicio, borra el token,
# retira el ajuste de sysctl y, con --purge, desinstala también el paquete, el usuario y el
# repositorio de Cloudflare.
#
# Uso:
#   sudo bash scripts/uninstall-cloudflared.sh            # conserva el paquete cloudflared
#   sudo bash scripts/uninstall-cloudflared.sh --purge    # además desinstala el paquete, el usuario y el repositorio

readonly CLOUDFLARE_KEYRING=/usr/share/keyrings/cloudflare-main.gpg
readonly CLOUDFLARE_LIST=/etc/apt/sources.list.d/cloudflared.list
readonly ENV_FILE=/etc/cloudflared/cloudflared.env
readonly UNIT_FILE=/etc/systemd/system/cloudflared.service
readonly SYSCTL_FILE=/etc/sysctl.d/99-cloudflared-quic.conf

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

parse_args() {
  purge=false
  case "${1:-}" in
    '') ;;
    --purge) purge=true ;;
    *) fail "Opción desconocida: $1 (solo se admite --purge)" ;;
  esac
}

stop_service() {
  systemctl disable --now cloudflared 2>/dev/null || true
  rm -f "$UNIT_FILE"
  systemctl daemon-reload
}

remove_token() {
  if [[ -f "$ENV_FILE" ]]; then
    shred -u "$ENV_FILE" 2>/dev/null || rm -f "$ENV_FILE"
  fi
  rmdir /etc/cloudflared 2>/dev/null || true
}

remove_quic_sysctl() {
  rm -f "$SYSCTL_FILE"
  sysctl --system >/dev/null
}

purge_package() {
  DEBIAN_FRONTEND=noninteractive apt-get remove -y cloudflared >/dev/null 2>&1 || true
  rm -f /usr/local/bin/cloudflared
  userdel cloudflared 2>/dev/null || true
  rm -f "$CLOUDFLARE_LIST" "$CLOUDFLARE_KEYRING"
  apt-get update >/dev/null 2>&1 || true
}

main() {
  [[ "${EUID}" -eq 0 ]] || fail "Ejecuta como root. Ejemplo: sudo bash $0"
  parse_args "$@"
  echo "[1/4] Deteniendo y deshabilitando el servicio..."
  stop_service
  echo "[2/4] Borrando el token y la configuración..."
  remove_token
  echo "[3/4] Retirando el ajuste de sysctl para QUIC..."
  remove_quic_sysctl
  if [[ "$purge" == true ]]; then
    echo "[4/4] Desinstalando el paquete, el usuario y el repositorio de Cloudflare..."
    purge_package
  else
    echo "[4/4] Paquete conservado (usa --purge para desinstalarlo)."
  fi
  echo "OK: el túnel ya no corre en este equipo. Recuerda borrar o rotar el conector en el panel de Cloudflare Zero Trust."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
