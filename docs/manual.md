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

## 1. Añadir el repositorio de Cloudflare

El paquete `cloudflared` no está en Debian ni en Ubuntu: viene del repositorio de paquetes de Cloudflare, firmado con su clave.

```bash
sudo apt-get install -y curl ca-certificates
sudo curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
```

## 2. Instalar cloudflared

```bash
sudo apt-get update
sudo apt-get install -y cloudflared
cloudflared --version
```

Algunas instalaciones antiguas dejaron una copia en `/usr/local/bin`. Para que `systemd` y la terminal usen el mismo binario:

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
EOF'
sudo systemctl daemon-reload
```

Fíjate en que `ExecStart` no lleva `--token`: `cloudflared` lee el token de la variable `TUNNEL_TOKEN` que systemd le pasa desde el archivo de entorno. Si fuera un argumento, cualquier usuario del equipo lo vería con `ps` o `systemctl status`. Por la misma vía se puede fijar `TUNNEL_TRANSPORT_PROTOCOL=http2` cuando la red bloquea QUIC (ver problemas frecuentes).

`--no-autoupdate` evita que el binario se actualice solo en casa del cliente; las actualizaciones llegan con `apt` cuando tú decidas. `Restart=on-failure` lo levanta si se cae y al reiniciar el equipo arranca solo. `TimeoutStartSec=0` es lo que usa el instalador oficial de Cloudflare: con redes lentas, el aviso de arranque puede tardar más de medio minuto. Las tres líneas `Protect*`/`PrivateTmp` limitan lo que el proceso puede tocar del sistema; el túnel solo necesita salir a la red.

El servicio se arranca en el paso siguiente, después del ajuste de kernel, para no reiniciarlo dos veces.

## 6. Ajustes de kernel para QUIC

`cloudflared` usa QUIC (UDP) y Cloudflare recomienda búferes mayores que los de Linux por defecto. Sin esto funciona, pero los registros muestran avisos de `failed to sufficiently increase receive buffer size`.

Crea `/etc/sysctl.d/99-cloudflared-quic.conf`:

```conf
net.core.rmem_max=7500000
net.core.wmem_max=7500000
net.core.rmem_default=2621440
net.core.wmem_default=2621440
```

Aplica y arranca el servicio:

```bash
sudo sysctl --system
sudo systemctl enable --now cloudflared
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
| `E: Unable to locate package cloudflared` | Falta el repositorio de Cloudflare (paso 1). El script lo añade solo; a mano, repite el paso 1 y luego `sudo apt-get update`. |
| Registros con `failed to dial to edge ... quic` y el túnel tarda en conectar | La red del cliente bloquea UDP 7844. Añade la línea `TUNNEL_TRANSPORT_PROTOCOL=http2` a `/etc/cloudflared/cloudflared.env` y reinicia el servicio; no hace falta tocar la unidad. |
| `failed to sufficiently increase receive buffer size` | Falta el paso 6 o no se aplicó: `sudo sysctl --system`. Es un aviso, no un fallo. |
| El túnel está HEALTHY pero el nombre público da **502** | El servicio local no responde en la dirección configurada en Public Hostname. Prueba desde el propio equipo con `curl -I http://localhost:8080`. |
| El servicio no arranca tras un reinicio | `systemctl is-enabled cloudflared` debe decir `enabled`. Si la red tarda, `After=network-online.target` ya lo contempla; revisa `journalctl -b -u cloudflared`. |
| Hay dos `cloudflared` corriendo | Una instalación anterior dejó otro servicio (por ejemplo `cloudflared-<nombre>`). Lista con `systemctl list-units 'cloudflared*'` y deshabilita el sobrante. |

## Rotar el token

Si el token se expuso: en el panel, **Tunnels → el túnel → Refresh token**, pega el nuevo en `/etc/cloudflared/cloudflared.env` (paso 4) y `sudo systemctl restart cloudflared`. El antiguo deja de valer al instante.

## Desinstalar

```bash
sudo bash scripts/uninstall-cloudflared.sh          # quita servicio, token y sysctl
sudo bash scripts/uninstall-cloudflared.sh --purge  # además desinstala el paquete, el usuario y el repositorio
```

Después, borra el túnel en el panel de Cloudflare para que el nombre público deje de existir.
