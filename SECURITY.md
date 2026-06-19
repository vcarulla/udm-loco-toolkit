# Seguridad

## Modelo de amenaza

Estas herramientas son para **uso local en una red doméstica de confianza**, ejecutadas a
mano por el dueño de la red. Supuestos:

- La máquina que las corre es de confianza (un solo usuario).
- La LAN entre esa máquina y la UDM/LOCO es de confianza.
- No hay exposición remota ni ejecución multiusuario.

Fuera de alcance (si querés esto, hace falta endurecer más): operación remota, entornos
compartidos, defensa contra un atacante con acceso a la LAN.

## Secretos

- Las credenciales (`UDM_*`) y los datos GPON (`LOCO_*`) viven **solo** en `.env`, que está
  en `.gitignore`. Ningún valor real está hardcodeado en el código.
- `private/` (credenciales, topología real) está gitignoreado salvo su `README.md`.
- La sesión de la API (`.udm-session/`) se guarda con permisos `700`/`600` y está ignorada.
- Los backups de firmware (`dumps/`, `patched/`) contienen el serial GPON clonado y están
  ignorados.
- `ufiber_patch.sh` **no loguea** serial ni MAC; `history.log` (`*.log`) está ignorado.
- Poné `.env` en `600`: `chmod 600 .env`.

## TLS

`udm-api.sh` habla con la UDM por HTTPS. La UDM trae un certificado **self-signed**, así que
por defecto `UDM_INSECURE_TLS=true` (equivale a `curl -k`). Esto es razonable en una LAN de
confianza pero deja la puerta a un MITM local. Para verificar de verdad:

```ini
UDM_INSECURE_TLS=false
UDM_CACERT=/ruta/al/ca.pem
```

## Supply-chain (UFiber.Configurator)

`UFiber.Configurator` es un binario de **terceros** (.NET 5, macOS x86_64). Riesgos:

- No auditamos su código fuente; solo fijamos su integridad por hash.
- .NET 5 está fuera de soporte (mayo 2022).

Mitigaciones:

- `UniFi_Loco_Patch/checksums.txt` fija el SHA256 del binario y las dylibs.
  Verificá: `cd UniFi_Loco_Patch && shasum -a 256 -c checksums.txt`.
- `scripts/download-ufiber-configurator.sh` permite traerlo del release upstream verificando
  el checksum, en vez de versionar el binario.

## Operaciones destructivas

`patch` y `restore` reescriben el firmware GPON del LOCO. Salvaguardas en `ufiber_patch.sh`:

- `set -Eeuo pipefail` (aborta ante el primer error).
- `patch` **exige un backup previo** o aborta.
- Validación de formato de vendor/serial/MAC antes de ejecutar.
- Lock (`mkdir` atómico) para evitar ejecuciones concurrentes.
- `--dry-run` para ver qué haría sin ejecutar `sudo`.
- `check` para validar el entorno antes de operar.

Regla de oro: **no toques el spoofing GPON salvo que se caiga la fibra**, y siempre con
`backup` reciente.

## Reportar

Es un proyecto personal. Si encontrás algo, abrí un issue.
