#!/usr/bin/env bash
set -euo pipefail

# NEZU - Cloudflare Tunnel en una MiniPC (ver docs/manual.md para el detalle de cada paso)
#
# Instala cloudflared desde el repositorio oficial de Cloudflare, crea un usuario sin privilegios,
# guarda el token en /etc/cloudflared/cloudflared.env, registra el servicio de systemd, aplica el
# ajuste de kernel para QUIC y comprueba que el túnel conecta.
#
# Uso:
#   export TUNNEL_TOKEN='<token del túnel>'
#   sudo -E bash scripts/setup-cloudflared.sh
#
# Vuelve a ejecutarse sin problema: cada paso deja el sistema igual si ya estaba hecho.

readonly CLOUDFLARE_KEYRING=/usr/share/keyrings/cloudflare-main.gpg
readonly CLOUDFLARE_LIST=/etc/apt/sources.list.d/cloudflared.list
readonly CLOUDFLARE_REPO='deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main'
readonly ENV_FILE=/etc/cloudflared/cloudflared.env
readonly UNIT_FILE=/etc/systemd/system/cloudflared.service
readonly SYSCTL_FILE=/etc/sysctl.d/99-cloudflared-quic.conf
readonly CONNECT_WAIT_SEC=30

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

check_prerequisites() {
  [[ "${EUID}" -eq 0 ]] || fail "Ejecuta como root. Ejemplo: sudo -E bash $0"
  command -v apt-get >/dev/null || fail "Este runbook es para Debian o Ubuntu (necesita apt-get)."
  command -v systemctl >/dev/null || fail "Este runbook necesita systemd."
  if [[ -z "${TUNNEL_TOKEN:-}" ]]; then
    echo "ERROR: Falta TUNNEL_TOKEN. Ejemplo:" >&2
    echo "  export TUNNEL_TOKEN='<token del túnel>'" >&2
    echo "  sudo -E bash $0" >&2
    exit 1
  fi
}

# El paquete cloudflared no está en Debian ni en Ubuntu: hay que añadir el repositorio de Cloudflare.
add_cloudflare_repo() {
  if ! command -v curl >/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates
  fi
  install -d -m 0755 /usr/share/keyrings
  if [[ ! -s "$CLOUDFLARE_KEYRING" ]]; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o "$CLOUDFLARE_KEYRING"
    chmod 0644 "$CLOUDFLARE_KEYRING"
  fi
  if [[ ! -f "$CLOUDFLARE_LIST" ]] || ! grep -qF "$CLOUDFLARE_REPO" "$CLOUDFLARE_LIST"; then
    printf '%s\n' "$CLOUDFLARE_REPO" >"$CLOUDFLARE_LIST"
  fi
}

install_cloudflared() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflared
  # Instalaciones antiguas dejaron una copia en /usr/local/bin; systemd y la terminal deben usar la misma.
  if [[ -e /usr/local/bin/cloudflared && ! /usr/local/bin/cloudflared -ef /usr/bin/cloudflared ]]; then
    rm -f /usr/local/bin/cloudflared
    ln -s /usr/bin/cloudflared /usr/local/bin/cloudflared
  fi
  hash -r
}

create_service_user() {
  getent passwd cloudflared >/dev/null || useradd -r -s /usr/sbin/nologin -U cloudflared
  install -d -m 0750 -o root -g cloudflared /etc/cloudflared
}

# Solo root escribe el token y solo el grupo cloudflared lo lee. El servicio lo toma de aquí como
# variable de entorno: nunca va en la línea de comandos, donde cualquier usuario lo vería con `ps`.
write_env_file() {
  (
    umask 077
    printf 'TUNNEL_TOKEN=%s\n' "$TUNNEL_TOKEN" >"$ENV_FILE"
  )
  chown root:cloudflared "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
}

write_unit_file() {
  cat >"$UNIT_FILE" <<'EOF'
[Unit]
Description=cloudflared (Cloudflare Tunnel)
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
# TUNNEL_TOKEN (y, si hace falta, TUNNEL_TRANSPORT_PROTOCOL) llegan desde este archivo.
EnvironmentFile=/etc/cloudflared/cloudflared.env
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel run
Restart=on-failure
RestartSec=5s
TimeoutStartSec=0
User=cloudflared
Group=cloudflared
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

# Búferes UDP que recomienda Cloudflare para QUIC; sin ellos funciona, pero avisa en cada arranque.
apply_quic_sysctl() {
  cat >"$SYSCTL_FILE" <<'EOF'
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.rmem_default=2621440
net.core.wmem_default=2621440
EOF
  sysctl --system >/dev/null
}

start_service() {
  systemctl enable --now cloudflared
  systemctl restart cloudflared
}

verify_tunnel() {
  local waited=0
  while (( waited < CONNECT_WAIT_SEC )); do
    if journalctl -u cloudflared --since "-${CONNECT_WAIT_SEC}s" --no-pager 2>/dev/null \
        | grep -q 'Registered tunnel connection'; then
      return 0
    fi
    systemctl is-active --quiet cloudflared || break
    sleep 2
    waited=$((waited + 2))
  done
  echo "AVISO: el túnel no confirmó la conexión en ${CONNECT_WAIT_SEC} s. Estado y registros:" >&2
  systemctl status cloudflared --no-pager || true
  journalctl -u cloudflared -n 30 --no-pager || true
  return 1
}

main() {
  check_prerequisites
  echo "[1/7] Añadiendo el repositorio de paquetes de Cloudflare..."
  add_cloudflare_repo
  echo "[2/7] Instalando cloudflared..."
  install_cloudflared
  echo "[3/7] Creando el usuario y el directorio del servicio..."
  create_service_user
  echo "[4/7] Guardando el token en ${ENV_FILE}..."
  write_env_file
  echo "[5/7] Registrando el servicio de systemd..."
  write_unit_file
  echo "[6/7] Aplicando el ajuste de kernel para QUIC y arrancando el servicio..."
  apply_quic_sysctl
  start_service
  echo "[7/7] Comprobando que el túnel conecta..."
  if verify_tunnel; then
    echo "OK: cloudflared instalado y conectado. En el panel de Cloudflare el túnel debe aparecer HEALTHY."
  else
    echo "El servicio queda instalado; revisa el token y la salida de red. Más en docs/manual.md (Problemas frecuentes)." >&2
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
