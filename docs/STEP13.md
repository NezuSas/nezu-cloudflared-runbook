# Paso 13 - Procedimiento para replicar en otra mini-PC (runbook)

## 1) Instalar cloudflared
```bash
sudo apt-get update
sudo apt-get install -y cloudflared
```

## 2) Unificar binario
```bash
sudo rm -f /usr/local/bin/cloudflared
sudo ln -s /usr/bin/cloudflared /usr/local/bin/cloudflared
hash -r
```

## 3) Crear usuario y directorio
```bash
getent passwd cloudflared >/dev/null || sudo useradd -r -s /usr/sbin/nologin -U cloudflared
sudo install -d -m 0750 -o root -g cloudflared /etc/cloudflared
```

## 4) Crear env con token del conector (del túnel correspondiente)
```bash
sudo bash -c 'umask 077; cat > /etc/cloudflared/cloudflared.env <<EOF
TUNNEL_TOKEN=<TOKEN_AQUI>
EOF'
sudo chown root:cloudflared /etc/cloudflared/cloudflared.env
sudo chmod 0640 /etc/cloudflared/cloudflared.env
```

## 5) Crear servicio systemd
```bash
sudo bash -c 'cat > /etc/systemd/system/cloudflared.service <<'"'"'EOF'"'"'
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
EOF'
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared
```

## 6) Aplicar sysctl QUIC (recomendado)
Crear:
`/etc/sysctl.d/99-cloudflared-quic.conf`

```conf
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.rmem_default=2621440
net.core.wmem_default=2621440
```

Aplicar:
```bash
sudo sysctl --system
sudo systemctl restart cloudflared
```

## 7) Validar
```bash
systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 50 --no-pager
```
