# Manual: Cloudflare Tunnel en una MiniPC, paso a paso

Este documento hace a mano, y explica, lo mismo que `scripts/setup-cloudflared.sh` hace de una vez. Sirve para auditar el script, para equipos donde no se quiera ejecutar nada sin leerlo, o para entender qué queda instalado.

Para usar el script en lugar de los pasos a mano:

```bash
sudo bash scripts/setup-cloudflared.sh
```

El script pide el token sin mostrarlo, así no queda en el historial de la terminal. Para instalar sin preguntas, por ejemplo desde otro script, pásalo en la variable `TUNNEL_TOKEN` con `sudo --preserve-env=TUNNEL_TOKEN bash scripts/setup-cloudflared.sh`, que pasa a root solo esa variable. No uses `sudo -E`: el `sudo-rs` que trae Ubuntu 26.04 lo ignora sin avisar y el token no llega.

Funciona en equipos x86_64 y arm64. Cloudflare publica `cloudflared` para ambas arquitecturas en su repositorio, y el runbook se probó completo en una Raspberry Pi 4 con Ubuntu 26.04.

La sección 8 explica cómo dar también acceso por SSH al equipo, protegido con Cloudflare Access.

## Qué consigues

Un servicio `cloudflared` que mantiene una conexión saliente permanente con Cloudflare. Cloudflare publica el nombre que tú elijas (por ejemplo `casa.ejemplo.com`) y lo encamina por esa conexión hacia el servicio local que indiques (por ejemplo `http://localhost:8080`). El router del cliente no abre ningún puerto; el equipo solo hace conexiones de salida.

## 0. Obtener el token del túnel

1. Entra en [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) con la cuenta que administra el dominio.
2. **Networks → Tunnels → Create a tunnel**, tipo **Cloudflared**. Ponle el nombre del cliente o del equipo.
3. En la pantalla de instalación, Cloudflare muestra un comando con `--token eyJ…`. Copia **solo el token** (la cadena larga que empieza por `eyJ`). Ese es `TUNNEL_TOKEN`.
4. Publica el servicio local en el túnel. Según la versión del panel, la opción se llama **Public Hostname** o **Published application**. Rellena:
   - **Subdomain** y **Domain**: el nombre público, por ejemplo `casa` en `ejemplo.com`.
   - **Service URL**, o **Type** y **URL** en el panel antiguo: el servicio local, por ejemplo `http://localhost:8080`.

   En el panel nuevo no hay un desplegable de tipo: el tipo va al principio de la URL. `http://` publica una página web; `ssh://` publica el SSH del equipo (sección 8). Esto se puede cambiar después sin tocar el equipo.

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

Solo `root` lo escribe y solo el grupo `cloudflared` lo lee. El token se pide sin mostrarlo y se escribe en el archivo sin pasar nunca por la línea de comandos, así no queda en el historial ni se ve con `ps`:

```bash
read -rsp 'Pega el token del túnel y pulsa Enter: ' TUNNEL_TOKEN; echo
printf 'TUNNEL_TOKEN=%s\n' "$TUNNEL_TOKEN" \
  | sudo install -m 0640 -o root -g cloudflared /dev/stdin /etc/cloudflared/cloudflared.env
unset TUNNEL_TOKEN
```

`printf` es una orden interna de la shell, así que el token no aparece como argumento de ningún proceso. No escribas el token directamente en un comando como `echo 'TUNNEL_TOKEN=eyJ…'`: quedaría en el historial.

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

## 8. Acceso por SSH con Cloudflare Access (opcional)

El mismo túnel puede dar acceso por SSH al equipo desde cualquier red, sin abrir el puerto 22 en el router. El SSH nunca debe publicarse sin **Access** delante: sin él, cualquiera que conozca el nombre llega a la pantalla de contraseña del equipo.

Quedan tres capas: Access exige iniciar sesión con una identidad autorizada, el túnel comprueba en el propio equipo el token que firma Access, y SSH sigue pidiendo su clave o contraseña.

### 8.1 Publicar el SSH en el túnel

En el túnel, añade otra aplicación publicada:

- **Subdomain** y **Domain**: por ejemplo `ssh-casa` en `ejemplo.com`.
- **Service URL**: `ssh://localhost:22`. Con `http://localhost:22` la conexión falla: Cloudflare le hablaría en web al servidor SSH (ver problemas frecuentes).

Guarda con el interruptor **Protect with Access** apagado; se activa en el paso 8.3, cuando la aplicación de Access ya existe.

### 8.2 Crear la aplicación de Access

En Zero Trust, **Access → Applications → Add an application → Self-hosted**:

1. **Public hostnames**: el mismo nombre del paso 8.1, por ejemplo `ssh-casa` en `ejemplo.com`, sin ruta.
2. **Browser rendering**: déjalo en **Off** si se va a entrar desde una terminal.
3. **Access policies**: una política **Allow** cuya regla **Include** sea **Emails** con los correos autorizados. Puedes reutilizar una política existente con **Add current policies**.
4. **Authentication**: deja **Accept all available identity providers**. Con un solo método de inicio de sesión, **Apply instant authentication** evita elegirlo cada vez.
5. **Details**: un nombre reconocible, por ejemplo «SSH casa». La duración de sesión de 24 horas es razonable.
6. Guarda. Abre la aplicación y copia su **Application Audience (AUD) Tag**, una cadena de 64 caracteres; está en la vista general o en **Additional settings**.

Desde este momento, quien abra el nombre sin sesión acaba en la pantalla de inicio de sesión de Cloudflare.

### 8.3 Proteger el túnel con Access

Vuelve a la aplicación publicada del paso 8.1, abre **Access** dentro de sus ajustes adicionales y activa **Protect with Access**:

- **Team name**: el nombre de tu equipo de Zero Trust, la parte inicial de `<equipo>.cloudflareaccess.com`.
- **Application Audience (AUD) tag**: pega la etiqueta del paso 8.2 y **pulsa Enter**. Debe quedar como una pastilla; si solo la pegas, el panel responde «Add at least one AUD tag when Protect with Access is on» y no guarda.

Guarda los cambios. El equipo recibe la configuración en unos segundos, sin reiniciar nada.

### 8.4 Conectarse desde el PC

En el PC desde el que entras hace falta `cloudflared`: en Windows, el instalador de Cloudflare o `winget install --id Cloudflare.cloudflared`; en Linux y macOS, el paquete de su repositorio o Homebrew. Después, añade una entrada a `~/.ssh/config`. En Windows:

```text
Host casa-ssh
  HostName ssh-casa.ejemplo.com
  User <usuario del equipo>
  ProxyCommand "C:\Program Files (x86)\cloudflared\cloudflared.exe" access ssh --hostname ssh-casa.ejemplo.com
```

En Linux y macOS, la misma entrada con `ProxyCommand cloudflared access ssh --hostname %h`. Si usas una clave concreta, añade `IdentityFile` e `IdentitiesOnly yes`.

La primera vez, `ssh casa-ssh` abre el navegador para iniciar sesión en Access; si no se abre, la terminal muestra el enlace. La sesión queda guardada en `~/.cloudflared/` durante lo que dure la sesión de la aplicación, 24 horas en el ejemplo.

### 8.5 Verificar la huella del equipo

En la primera conexión SSH pregunta si confías en la huella del servidor, porque el nombre es nuevo para tu PC. No la aceptes a ciegas:

- Si ya entrabas al equipo por la red local, su huella está en `~/.ssh/known_hosts` con la IP local. Es el mismo servidor, así que puedes copiar esa línea cambiando la IP por el nombre del túnel.
- Si no, compárala con la que muestra el propio equipo: `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.

### 8.6 Comprobar

```bash
ssh casa-ssh hostname
```

Debe responder el nombre del equipo. Sin sesión de Access, `curl -I https://ssh-casa.ejemplo.com` devuelve una redirección (302) a `<equipo>.cloudflareaccess.com`: es la prueba de que Access está delante.

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
| `ERROR: Falta el token del túnel` | El script no se ejecutó en una terminal y no recibió `TUNNEL_TOKEN`; o se usó `sudo -E` en un sistema con `sudo-rs` (Ubuntu 26.04 y posteriores), que ignora `-E`. Ejecútalo en una terminal para que pida el token, o con `sudo --preserve-env=TUNNEL_TOKEN`. |
| `websocket: bad handshake` al hacer `ssh`, y en el equipo `malformed HTTP status` en `journalctl -u cloudflared` | El nombre del SSH está publicado como `http://localhost:22`. Cámbialo a `ssh://localhost:22` en el panel (sección 8.1). |
| «Add at least one AUD tag when Protect with Access is on» | La etiqueta AUD se pegó pero no se añadió: haz clic en el campo, pega y pulsa Enter hasta que quede como pastilla (sección 8.3). |
| `Host key verification failed` en la primera conexión por el túnel | Tu PC no conoce aún la huella con el nombre nuevo. Verifícala y añádela (sección 8.5). |
| El SSH por la red local deja de responder tras varios intentos seguidos | Si el equipo tiene `ufw limit` en el puerto 22, bloquea más de seis conexiones en 30 segundos, y cada reintento alarga el bloqueo. Espera un minuto sin intentar nada y agrupa las órdenes en una sola conexión. |

## Rotar el token

Si el token se expuso: en el panel, **Tunnels → el túnel → Refresh token**. Después guarda el nuevo como en el paso 4, o vuelve a ejecutar el script, que lo pide y reescribe el archivo, y reinicia con `sudo systemctl restart cloudflared`. El antiguo deja de valer al instante.

## Desinstalar

```bash
sudo bash scripts/uninstall-cloudflared.sh          # quita servicio, token y sysctl
sudo bash scripts/uninstall-cloudflared.sh --purge  # además desinstala el paquete, el usuario y el repositorio
```

Después, borra el túnel en el panel de Cloudflare para que el nombre público deje de existir. Si diste acceso por SSH, borra también su aplicación de Access y quita la entrada de `~/.ssh/config` y la línea de su nombre en `~/.ssh/known_hosts` del PC.
