# UniFi_Loco_Patch

Herramientas para parchear el **UF-LOCO** (ONU GPON): spoofing del vendor/serial/MAC del
ONT original, backup y restore.

## Atribución

El binario **`UFiber.Configurator`** (y sus `.dylib`) es software de **terceros**.
Lo único propio de este repo es el wrapper `ufiber_patch.sh`, que automatiza las llamadas
al configurador (check → backup → patch → restore → log).

Recursos útiles:

- Proyecto parcheador: https://github.com/Unifi-Tools/UFiber.Configurator
- Manual oficial UF-LOCO: https://dl.ubnt.com/qsg/UF-LOCO/UF-LOCO_ES.html
- Firmware originales: https://ui.com/download/ufiber

## Binario incluido (verificación)

`UFiber.Configurator` es un build **.NET 5** para **macOS x86_64** (en Apple Silicon corre
vía Rosetta 2; .NET 5 está fuera de soporte desde mayo 2022). Su licencia es la del proyecto
upstream — revisala ahí antes de redistribuir.

Su integridad está fijada en `checksums.txt`. Verificá antes de ejecutarlo:

```bash
shasum -a 256 -c checksums.txt
```

Alternativa: en vez de versionar el binario, traerlo del release upstream con
`../scripts/download-ufiber-configurator.sh` (descarga + verifica checksum).

## Uso

> ⚠️ Solo funciona con la PC conectada **directo** al LOCO. `patch`/`restore` reescriben
> el firmware GPON — `patch` **exige** un backup previo. Los valores vendor/serial/MAC se
> toman de `LOCO_*` en `../.env` (no hay valores hardcodeados; se valida su formato).

```bash
./ufiber_patch.sh check                # valida entorno sin tocar nada
./ufiber_patch.sh backup               # dump del firmware actual → dumps/
./ufiber_patch.sh patch                # aplica el spoofing GPON (requiere backup previo)
./ufiber_patch.sh patch --dry-run      # muestra qué haría, sin ejecutar sudo
./ufiber_patch.sh restore              # restaura el último backup
./ufiber_patch.sh log                  # historial de acciones
```
