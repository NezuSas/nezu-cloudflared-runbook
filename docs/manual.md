# Manual: Cloudflare Tunnel en una MiniPC, paso a paso

Este documento hace a mano, y explica, lo mismo que `scripts/setup-cloudflared.sh` hace de una vez. Sirve para auditar el script, para equipos donde no se quiera ejecutar nada sin leerlo, o para entender qué queda instalado.

## Qué consigues

Un servicio `cloudflared` que mantiene una conexión saliente permanente con Cloudflare. Cloudflare publica el nombre que tú elijas (por ejemplo `casa.ejemplo.com`) y lo encamina por esa conexión hacia el servicio local que indiques (por ejemplo `http://localhost:8080`). El router del cliente no abre ningún puerto; el equipo solo hace conexiones de salida.

## 0. Obtener el token del túnel

1. Entra en [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) con la cuenta que administra el dominio.
2. **Networks → Tunnels → Create a tunnel**, tipo **Cloudflared**. Ponle el nombre del cliente o del equipo.
3. En la pantalla de instalación, Cloudflare muestra un comando con `--token eyJ…`. Copia **solo el token** (la cadena larga que empieza por `eyJ`). Ese es `TUNNEL_TOKEN`.
4. En **Public Hostname**, añade el nombre público y el servicio local al que debe llegar, por ejemplo `http://localhost:8080`. Esto se puede cambiar después sin tocar el equipo.

El token identifica al conector: trátalo como una contraseña. No lo pegues en archivos del repositorio, chats ni capturas.

## 1. Instalar cloudflared

```bash
sudo apt-get update
sudo apt-get install -y cloudflared
```

Si `apt` no encuentra el paquete, añade el repositorio oficial de Cloudflare siguiendo [su guía](https://pkg.cloudflare.com/) y repite el paso.

## 2. Unificar el binario

Algunas instalaciones antiguas dejaron una copia en `/usr/local/bin`. Para que `systemd` y la terminal usen el mismo:

```bash
sudo rm -f /usr/local/bin/cloudflared
sudo ln -s /usr/bin/cloudflared /usr/local/bin/cloudflared
hash -r
```

## 3. Usuario y directorio del servicio

El servicio corre con un usuario sin shell ni privilegios:

```bash
getent passwd cloudflared >/dev/null || sudo useradd -r -s /usr/sbin/nologin -U cloudflared
sudo install -d -m 0750 -o root -g cloudflared /etc/cloudflared
```

## 4. Guardar el token

Solo `root` lo escribe y solo el grupo `cloudflared` lo lee:

```bash
sudo bash -c 'umask 077; cat > /etc/cloudflared/cloudflared.env <<EOF
TUNNEL_TOKEN=<TOKEN_AQUI>
EOF'
sudo chown root:cloudflared /etc/cloudflared/cloudflared.env
sudo chmod 0640 /etc/cloudflared/cloudflared.env
```

## 5. Servicio de systemd

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

`--no-autoupdate` evita que el binario se actualice solo en casa del cliente; las actualizaciones llegan con `apt` cuando tú decidas. `Restart=on-failure` lo levanta si se cae; al reiniciar el equipo arranca solo.

## 6. Ajustes de kernel para QUIC

`cloudflared` usa QUIC (UDP) y Cloudflare recomienda búferes mayores que los de Linux por defecto. Sin esto funciona, pero los registros muestran avisos de `failed to sufficiently increase receive buffer size`.

Crea `/etc/sysctl.d/99-cloudflared-quic.conf`:

```conf
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.rmem_default=2621440
net.core.wmem_default=2621440
```

Aplica y reinicia el servicio:

```bash
sudo sysctl --system
sudo systemctl restart cloudflared
```

## 7. Comprobar

```bash
systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 50 --no-pager
```

En los registros debe aparecer `Registered tunnel connection` varias veces (una por cada centro de datos al que se conecta). En el panel de Cloudflare, el túnel pasa a **HEALTHY**. Abre el nombre público desde fuera de la red del cliente para confirmar que llega al servicio local.

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| `Unauthorized: Invalid tunnel secret` o `failed to parse token` | El token está incompleto o pertenece a otro túnel. Vuelve a copiarlo del panel y reescribe `/etc/cloudflared/cloudflared.env`. |
| Registros con `failed to dial to edge ... quic` y el túnel tarda en conectar | La red del cliente bloquea UDP 7844. Fuerza HTTP/2 añadiendo `--protocol http2` al `ExecStart` y reinicia el servicio. |
| `failed to sufficiently increase receive buffer size` | Falta el paso 6 o no se aplicó: `sudo sysctl --system`. Es un aviso, no un fallo. |
| El túnel está HEALTHY pero el nombre público da **502** | El servicio local no responde en la dirección configurada en Public Hostname. Prueba desde el propio equipo con `curl -I http://localhost:8080`. |
| El servicio no arranca tras un reinicio | `systemctl is-enabled cloudflared` debe decir `enabled`. Si la red tarda, `After=network-online.target` ya lo contempla; revisa `journalctl -b -u cloudflared`. |
| Hay dos `cloudflared` corriendo | Una instalación anterior dejó otro servicio (por ejemplo `cloudflared-<nombre>`). Lista con `systemctl list-units 'cloudflared*'` y deshabilita el sobrante. |

## Rotar el token

Si el token se expuso: en el panel, **Tunnels → el túnel → Refresh token**, pega el nuevo en `/etc/cloudflared/cloudflared.env` (paso 4) y `sudo systemctl restart cloudflared`. El antiguo deja de valer al instante.

## Desinstalar

```bash
sudo bash scripts/uninstall-cloudflared.sh          # quita servicio, token y sysctl
sudo bash scripts/uninstall-cloudflared.sh --purge  # además desinstala el paquete y el usuario
```

Después, borra el túnel en el panel de Cloudflare para que el nombre público deje de existir.
