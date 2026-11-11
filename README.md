<div align="center">
  <img src=".github/banner.svg" alt="NEZU · Runbook para Cloudflare Tunnel en una MiniPC" width="100%">
</div>

# Cloudflare Tunnel en una MiniPC

> **In English.** An executable runbook that installs `cloudflared` as a hardened systemd service on a Debian or Ubuntu mini PC, with the QUIC kernel tuning Cloudflare recommends, so a device in a customer's home is reachable without opening router ports. Includes a step-by-step manual, troubleshooting and an uninstaller. Apache 2.0.

Runbook **ejecutable** para dar acceso remoto seguro a una MiniPC instalada en casa de un cliente, sin abrir puertos en su router: instala `cloudflared`, lo deja como servicio de systemd y ajusta el kernel para QUIC. Es el paso que NEZU repite en cada appliance nuevo, convertido en un script para que salga igual todas las veces.

El repositorio no contiene secretos. El token del túnel se inyecta por variable de entorno en el momento de instalar y queda solo en el host.

## Requisitos

- Debian o Ubuntu con `apt`.
- Usuario con `sudo`.
- Un **token de túnel** válido de Cloudflare Zero Trust. Cómo crearlo, en [`docs/manual.md`](docs/manual.md#0-obtener-el-token-del-túnel).

## Uso

```bash
git clone https://github.com/NezuSas/nezu-cloudflared-runbook.git
cd nezu-cloudflared-runbook
```

Exporta el token solo en la sesión actual. No lo escribas en ningún archivo del repositorio:

```bash
export TUNNEL_TOKEN='<token del túnel>'
```

Instala y arranca el servicio:

```bash
sudo --preserve-env=TUNNEL_TOKEN bash scripts/setup-cloudflared.sh
```

`--preserve-env=TUNNEL_TOKEN` pasa a root solo el token. No uses `sudo -E`: el `sudo-rs` de Ubuntu 26.04 lo ignora sin avisar y el script se detiene diciendo que falta `TUNNEL_TOKEN`.

Comprueba:

```bash
systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 50 --no-pager
```

## Qué hace el script

1. Añade el repositorio de paquetes de Cloudflare (el paquete no está en Debian ni en Ubuntu) e instala `cloudflared`.
2. Crea el usuario `cloudflared`, sin shell, y el directorio `/etc/cloudflared`.
3. Guarda el token en `/etc/cloudflared/cloudflared.env` con permisos `0640` y propietario `root:cloudflared`. El servicio lo lee de ahí como variable de entorno: nunca aparece en la línea de comandos ni en `ps`.
4. Registra el servicio en systemd con reinicio automático y el proceso acotado (`NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, `PrivateTmp`).
5. Aplica los ajustes de `sysctl` que recomienda Cloudflare para QUIC y arranca el servicio.
6. Espera a que los registros confirmen `Registered tunnel connection`; si no llega en 30 segundos, muestra el estado y termina con error.

Se puede volver a ejecutar las veces que haga falta: cada paso deja el equipo igual si ya estaba hecho. El detalle, para hacerlo a mano o auditarlo, está en [`docs/manual.md`](docs/manual.md), junto con la obtención del token, los problemas frecuentes y cómo rotarlo.

## Desinstalar

```bash
sudo bash scripts/uninstall-cloudflared.sh          # detiene el servicio y borra token, unidad y sysctl
sudo bash scripts/uninstall-cloudflared.sh --purge  # además desinstala el paquete, el usuario y el repositorio
```

## Problemas frecuentes

| Síntoma | Qué hacer |
|---|---|
| `Invalid tunnel secret` | El token está incompleto o es de otro túnel: vuelve a copiarlo y reescribe `/etc/cloudflared/cloudflared.env`. |
| Tarda en conectar y los registros hablan de `quic` | La red bloquea UDP 7844: añade `TUNNEL_TRANSPORT_PROTOCOL=http2` a `/etc/cloudflared/cloudflared.env` y reinicia el servicio. |
| Túnel HEALTHY pero el nombre público da 502 | El servicio local no responde donde dice Public Hostname: prueba `curl -I http://localhost:8080` en el equipo. |

Más casos y su explicación, en el [manual](docs/manual.md#problemas-frecuentes).

## Estructura

```text
scripts/setup-cloudflared.sh         instalación y configuración del servicio
scripts/uninstall-cloudflared.sh     desinstalación limpia
templates/cloudflared.env.template   plantilla del archivo de entorno, sin token
docs/manual.md                       manual paso a paso, token, problemas y rotación
CHANGELOG.md                         cambios de cada versión
```

Los scripts pasan `shellcheck` sin avisos y están escritos como funciones, de modo que cada paso se puede ejecutar y probar por separado; así se comprobó la instalación en un contenedor Debian limpio.

## Seguridad

- Nunca confirmes tokens, credenciales ni archivos `.env` con valores reales.
- El token da acceso al túnel: trátalo como una contraseña y rótalo si se expone. En el equipo solo lo lee `root` y el grupo `cloudflared`, y nunca viaja como argumento del proceso.
- La ruta pública la define el túnel en el panel de Cloudflare; este script no abre nada hacia internet por sí mismo.
- El paquete se instala desde el repositorio oficial de Cloudflare, firmado con su clave, nunca desde un binario descargado a mano.

## ¿Lo necesitas en tu instalación?

Este runbook es gratuito: lo publicamos porque es el que usamos en nuestros propios equipos. Si quieres acceso remoto seguro a tus equipos sin abrir puertos y prefieres que lo montemos y lo mantengamos nosotros, [cuéntanos qué necesitas](https://nezuecuador.com/es/contacto) y te respondemos con una propuesta concreta. Aquí está [lo que hacemos](https://nezuecuador.com/es/servicios).

## Licencia

Apache 2.0: puedes usar, modificar y redistribuir este código, también en proyectos comerciales, conservando el aviso de copyright. La licencia no concede derechos sobre la marca NEZU. Texto completo en [LICENSE](LICENSE).

---

<div align="center">
  <sub>Parte del ecosistema <a href="https://github.com/NezuSas">NEZU</a> · <a href="https://nezuecuador.com">nezuecuador.com</a> · © NEZU S.A.S. · Licencia Apache 2.0.</sub>
</div>
