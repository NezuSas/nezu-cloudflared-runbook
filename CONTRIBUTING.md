# Cómo contribuir

Gracias por el interés en Cloudflare Tunnel en una MiniPC. Este repositorio lo mantiene NEZU S.A.S. y lo publicamos para que clientes, integradores y colaboradores puedan consultarlo, instalarlo y proponer mejoras. Se publica bajo la [licencia Apache 2.0](LICENSE).

## Antes de empezar

- Para fallos de seguridad, sigue la [política de seguridad](SECURITY.md); no abras un issue público.
- Para un fallo o una propuesta, abre un issue con la plantilla que corresponda. Así acordamos el cambio antes de que escribas código.
- Para dudas de instalación o de uso en tu caso, también sirve un issue; si prefieres que lo hagamos nosotros, [escríbenos](https://nezuecuador.com/es/contacto).

## Pull requests

1. Parte de `main` en una rama con un nombre descriptivo.
2. Un cambio por pull request, pequeño y explicado: qué resuelve y cómo lo probaste.
3. Antes de enviarlo, ejecuta las comprobaciones del proyecto:

   ```bash
   bash -n scripts/*.sh
   shellcheck -S style scripts/*.sh   # o: docker run --rm -v "$PWD:/mnt" koalaman/shellcheck-alpine:stable shellcheck -S style /mnt/scripts/*.sh
   ```

   Los scripts están escritos como funciones y solo ejecutan `main` cuando se invocan directamente, así que un cambio se puede probar paso a paso haciendo `source` del script en un contenedor Debian limpio y llamando a cada función.
4. Anota el cambio en [CHANGELOG.md](CHANGELOG.md), en la sección de la próxima versión.
5. Mantén el estilo del código existente y no añadas dependencias sin justificarlas en la descripción.
6. No incluyas secretos, direcciones internas ni datos de clientes en código, pruebas ni capturas.

Revisamos cada pull request y respondemos en el propio hilo. Al enviarlo aceptas que tu aportación se publique bajo la licencia Apache 2.0 de este repositorio.

## Commits

Mensajes en imperativo y con prefijo de tipo, como en el historial: `fix: …`, `feat: …`, `docs: …`, `chore: …`.
