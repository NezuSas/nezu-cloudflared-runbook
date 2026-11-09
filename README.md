<div align="center">
  <img src=".github/banner.svg" alt="NEZU · Runbook para Cloudflare Tunnel en una MiniPC" width="100%">
</div>

# Cloudflare Tunnel en una MiniPC

Runbook **ejecutable** para dar acceso remoto seguro a una MiniPC instalada en casa de un cliente, sin abrir puertos en su router: instala `cloudflared`, lo deja como servicio de systemd y ajusta el kernel para QUIC. Es el paso que NEZU repite en cada appliance nuevo, convertido en un script para que salga igual todas las veces.

El repositorio no contiene secretos. El token del túnel se inyecta por variable de entorno en el momento de instalar y queda solo en el host.

## Requisitos

- Debian o Ubuntu con `apt`.
- Usuario con `sudo`.
- Un **token de túnel** válido de Cloudflare Zero Trust.

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
sudo -E bash scripts/setup-cloudflared.sh
```

Comprueba:

```bash
systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 50 --no-pager
```

## Qué hace el script

1. Instala `cloudflared` con `apt` y crea el usuario y los directorios del servicio.
2. Guarda el token en `/etc/cloudflared/cloudflared.env` con permisos `0640` y propietario `root:cloudflared`.
3. Registra y habilita el servicio `cloudflared` en systemd, con reinicio automático.
4. Aplica los ajustes de `sysctl` que recomienda Cloudflare para QUIC.

El detalle paso a paso, para hacerlo a mano o auditarlo, está en [`docs/STEP13.md`](docs/STEP13.md).

## Estructura

```text
scripts/setup-cloudflared.sh         instalación y configuración del servicio
templates/cloudflared.env.template   plantilla del archivo de entorno, sin token
docs/STEP13.md                       runbook documentado
```

## Seguridad

- Nunca confirmes tokens, credenciales ni archivos `.env` con valores reales.
- El token da acceso al túnel: trátalo como una contraseña y rótalo si se expone.
- La ruta pública la define el túnel en el panel de Cloudflare; este script no abre nada hacia internet por sí mismo.

## ¿Lo necesitas en tu instalación?

Este runbook es gratuito: lo publicamos porque es el que usamos en nuestros propios equipos. Si quieres acceso remoto seguro a tus equipos sin abrir puertos y prefieres que lo montemos y lo mantengamos nosotros, [cuéntanos qué necesitas](https://nezuecuador.com/es/contacto) y te respondemos con una propuesta concreta. Aquí está [lo que hacemos](https://nezuecuador.com/es/servicios).

---

<div align="center">
  <sub>Parte del ecosistema <a href="https://github.com/NezuSas">NEZU</a> · <a href="https://nezuecuador.com">nezuecuador.com</a> · © NEZU S.A.S. Publicado para clientes e integradores de NEZU.</sub>
</div>
