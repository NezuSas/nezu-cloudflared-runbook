# NEZU Cloudflared Runbook (MiniPC)

Este repositorio contiene un **runbook ejecutable** para replicar el **Paso 13** (Cloudflare Tunnel con `cloudflared` + systemd + sysctl QUIC) en una nueva mini-PC.

## Requisitos
- Debian/Ubuntu con `apt`
- Acceso con usuario con permisos sudo
- Un **Tunnel Token** válido (Cloudflare Zero Trust)

## Uso rápido

1) Clonar el repo:
```bash
git clone <TU_URL_PRIVADA_DEL_REPO>
cd nezu-cloudflared-runbook
```

2) Exportar el token (NO lo guardes en Git):
```bash
export TUNNEL_TOKEN='PEGA_AQUI_EL_TOKEN'
```

3) Ejecutar el instalador:
```bash
sudo -E bash scripts/setup-cloudflared.sh
```

4) Validar:
```bash
systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 50 --no-pager
```

## Seguridad
- Mantén este repo **privado**.
- No subas tokens, credenciales ni secretos a Git.
- El token se inyecta como variable de entorno y se guarda en el host en:
  - `/etc/cloudflared/cloudflared.env` (permisos 0640, root:cloudflared)

## Archivos
- `scripts/setup-cloudflared.sh`: instala y configura `cloudflared` como servicio.
- `templates/cloudflared.env.template`: plantilla de env (sin token real).
- `docs/STEP13.md`: runbook documentado.

