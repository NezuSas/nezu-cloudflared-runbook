# Cambios

Formato de [Keep a Changelog](https://keepachangelog.com/es/1.1.0/); versiones según [SemVer](https://semver.org/lang/es/).

## [Sin publicar]

### Añadido

- Sección 8 del manual, «Acceso por SSH con Cloudflare Access»: publicar el SSH en el túnel con `ssh://localhost:22`, crear la aplicación de Access con una política por correo, activar «Protect with Access» con la etiqueta AUD, conectarse desde el PC con `cloudflared access ssh` en `~/.ssh/config`, verificar la huella del equipo y comprobar que Access está delante. Resumen y enlace en el README.
- El manual y el README dicen que el runbook funciona en x86_64 y arm64, probado en una Raspberry Pi 4 con Ubuntu 26.04.
- Problemas frecuentes nuevos: «Falta TUNNEL_TOKEN» con `sudo -E`, «websocket: bad handshake» por publicar el SSH como `http://`, la etiqueta AUD que no se añade sin Enter, la huella desconocida en la primera conexión y el bloqueo de `ufw limit` tras varias conexiones seguidas.

### Cambiado

- El manual explica el panel nuevo de Cloudflare («Published application»), donde el tipo de servicio va al principio de la URL, y usa `sudo --preserve-env=TUNNEL_TOKEN` también en la forma de ejecutar el script.
- Desinstalar recuerda borrar la aplicación de Access y la configuración SSH del PC cuando se dio acceso por SSH.

## [1.0.1] - 2026-11-10

### Corregido

- En Ubuntu 26.04 la instalación se detenía con «Falta TUNNEL_TOKEN» aunque el token estuviera exportado: su `sudo-rs` ignora `sudo -E`. El README, la ayuda del script y sus mensajes de error usan ahora `sudo --preserve-env=TUNNEL_TOKEN`, que funciona con sudo y con sudo-rs y pasa a root solo el token. Encontrado al instalar el túnel en una Raspberry Pi 4 con Ubuntu 26.04 (arm64), donde el resto del runbook funcionó sin cambios.

## [1.0.0] - 2026-11-09

Primera versión numerada.

### Corregido

- El script de instalación fallaba en una máquina limpia: hacía `apt-get install cloudflared` sin añadir antes el repositorio de paquetes de Cloudflare, y ese paquete no está en Debian ni en Ubuntu. Ahora instala la clave y el repositorio oficiales (y `curl` si falta) antes de instalar.
- El token del túnel iba como argumento `--token` en el `ExecStart` del servicio, visible para cualquier usuario del equipo con `ps` o `systemctl status`. Ahora `cloudflared` lo lee de la variable `TUNNEL_TOKEN` que systemd le pasa desde `/etc/cloudflared/cloudflared.env`.

### Añadido

- El script comprueba al final que el túnel conecta (`Registered tunnel connection` en los registros) y termina con error, mostrando estado y registros, si no lo hace en 30 segundos.
- Comprobaciones previas: root, `apt-get`, `systemctl` y `TUNNEL_TOKEN`, con mensajes claros.
- `--purge` en la desinstalación retira también el repositorio y la clave de Cloudflare.
- `TUNNEL_TRANSPORT_PROTOCOL=http2` en el archivo de entorno como vía para redes que bloquean QUIC, sin editar la unidad; documentado en la plantilla, el manual y el README.
- `.gitattributes` para que los scripts se clonen siempre con finales de línea LF, también desde Windows.
- Este `CHANGELOG.md`.

### Cambiado

- Los scripts están escritos como funciones y solo ejecutan `main` al invocarse directamente, lo que permite probar cada paso por separado; pasan `shellcheck` sin avisos y la instalación se verificó en un contenedor Debian limpio.
- La unidad de systemd acota el proceso con `PrivateTmp`, `ProtectSystem=full` y `ProtectHome`, y usa `TimeoutStartSec=0` como el instalador oficial de Cloudflare.
- El ajuste de kernel para QUIC se aplica antes de arrancar el servicio, para no reiniciarlo dos veces.
- El manual separa en dos pasos el repositorio y la instalación, explica por qué el token no va en la línea de comandos y añade el error `Unable to locate package cloudflared` a los problemas frecuentes.

[1.0.1]: https://github.com/NezuSas/nezu-cloudflared-runbook/releases/tag/v1.0.1
[1.0.0]: https://github.com/NezuSas/nezu-cloudflared-runbook/releases/tag/v1.0.0
