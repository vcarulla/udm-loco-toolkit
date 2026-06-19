# Uso de los scripts

## `udm-menu.sh` — panel interactivo

```bash
./udm-menu.sh
```

Menú para la Dream Machine (vía `udm-api.sh`):

| Opción | Acción |
|---|---|
| 1 | Estado del gateway (temp/CPU/RAM) |
| 2 | WAN / Internet |
| 3 | Clientes conectados |
| 4 | Dispositivos UniFi |
| 5 | Redes configuradas |
| 6 | IDS/IPS (categorías + alertas) |
| 7 | Reiniciar un dispositivo |
| 8 | Query API libre (GET) |
| 9 | Re-login |
| F | Fiber / UF-LOCO (submenú: backup·patch·restore·log) |
| 0 | Salir |

Requiere `jq` (`brew install jq`) y las variables `UDM_*` en `.env`.

## `udm-api.sh` — cliente de la API

```bash
./udm-api.sh login
./udm-api.sh get  /proxy/network/api/s/default/stat/sta
./udm-api.sh post /proxy/network/api/s/default/cmd/devmgr '{"cmd":"...","mac":"..."}'
```

## `UniFi_Loco_Patch/ufiber_patch.sh` — parcheador del UF-LOCO

> ⚠️ Solo funciona con la PC conectada **directo** al LOCO y el DNS apuntándolo.
> `patch` y `restore` reescriben el firmware GPON — `patch` **exige** un backup previo.

```bash
cd UniFi_Loco_Patch
./ufiber_patch.sh check      # valida entorno (binario, .env, variables, backups)
./ufiber_patch.sh backup     # dump del firmware actual → dumps/
./ufiber_patch.sh patch      # aplica el spoofing GPON (requiere backup previo)
./ufiber_patch.sh restore    # restaura el último backup
./ufiber_patch.sh log        # historial de acciones
```

Antes de ejecutar de verdad, podés ver qué haría sin tocar nada:

```bash
./ufiber_patch.sh patch --dry-run
./ufiber_patch.sh restore --dry-run
```

Toma vendor/serial/MAC **exclusivamente** de `LOCO_*` en `.env`; valida su formato y
**aborta** si faltan o son inválidos (no hay valores por defecto).
