# udm-loco-toolkit

> Herramientas de red doméstica para Ubiquiti: gestión de la Dream Machine (UDM) + parcheo del UF-LOCO.

![Bash](https://img.shields.io/badge/Bash-5-4EAA25?logo=gnubash&logoColor=white)
![UniFi OS](https://img.shields.io/badge/UniFi%20OS-Dream%20Machine-0559C9?logo=ubiquiti&logoColor=white)

Scripts para administrar la red de casa montada sobre equipos **Ubiquiti**: una
**Dream Machine (UDM)** como gateway/router y un **UF-LOCO** (ONU GPON) que reemplaza
el ONT del ISP.

## Cadena de red

```
Fibra GPON ─→ UF-LOCO (bridge) ─→ Dream Machine ─→ LAN
```

El PPPoE lo hace la Dream Machine; el LOCO va en bridge transparente. Detalle completo
(IPs, VLANs, usuarios) en `private/RED.md`.

## Componentes

| Archivo | Qué hace |
|---|---|
| `udm-api.sh` | Cliente mínimo de la API local de UniFi OS (login + GET/POST/PUT/DELETE). |
| `udm-menu.sh` | Panel interactivo sobre `udm-api.sh` (estado, clientes, redes, IDS/IPS, reinicios) + submenú Fiber. |
| `UniFi_Loco_Patch/` | Parcheador del UF-LOCO (`ufiber_patch.sh` + `UFiber.Configurator`): spoofing GPON, backup y restore. |

## Uso rápido

```bash
cp .env.example .env     # completá tus credenciales y datos del LOCO
brew install jq          # dependencia de udm-menu.sh
./udm-menu.sh
```

Guía detallada de cada script en `public/USO.md`.

## Estructura

```
.
├── udm-api.sh              — cliente de la API del UDM
├── udm-menu.sh             — menú interactivo (incluye submenú Fiber)
├── UniFi_Loco_Patch/       — parcheador del UF-LOCO (binario de terceros + wrapper)
│   ├── ufiber_patch.sh     — wrapper (check/backup/patch/restore/log)
│   ├── UFiber.Configurator — binario de terceros (ver checksums.txt)
│   └── checksums.txt       — SHA256 del binario y dylibs
├── scripts/
│   └── download-ufiber-configurator.sh  — descarga/verifica el binario upstream
├── public/                 — notas/documentación compartible (USO.md, …)
├── private/                — credenciales, topología, datos GPON (NO versionado)
├── .env / .env.example     — variables (UDM_*, LOCO_*, UDM_INSECURE_TLS)
├── SECURITY.md             — modelo de amenaza, secretos, supply-chain
├── .editorconfig
└── .gitignore
```

## Configuración

Todo se centraliza en `.env` (ver `.env.example`):

| Variable | Para |
|---|---|
| `UDM_HOST` / `UDM_USER` / `UDM_PASS` | acceso a la Dream Machine |
| `LOCO_VENDOR_ID` / `LOCO_SERIAL` / `LOCO_MAC_WAN` | spoofing GPON del UF-LOCO |

> ⚠️ El spoofing GPON usa el serial/MAC clonados del ONT original: **no tocar** salvo
> que se caiga la fibra, y siempre con `backup` previo.

## Modelo de amenaza

Estos scripts están pensados para **uso local en una red doméstica de confianza**, operados
a mano por su dueño. **No** están diseñados para entornos multiusuario ni para exposición
remota. Detalle completo (manejo de secretos, TLS, supply-chain, backups) en
[`SECURITY.md`](SECURITY.md).

## Créditos y supply-chain

El parcheador del UF-LOCO se apoya en **UFiber.Configurator**, herramienta de terceros.
El binario incluido en `UniFi_Loco_Patch/` proviene de ese proyecto; lo único propio es el
wrapper `ufiber_patch.sh`.

- Proyecto: https://github.com/Unifi-Tools/UFiber.Configurator
- Manual UF-LOCO: https://dl.ubnt.com/qsg/UF-LOCO/UF-LOCO_ES.html
- Firmware: https://ui.com/download/ufiber

El binario es un build **.NET 5** para **macOS x86_64** (en Apple Silicon corre vía Rosetta 2;
.NET 5 está fuera de soporte desde mayo 2022). Su integridad está fijada en
`UniFi_Loco_Patch/checksums.txt`; verificá antes de confiar en él:

```bash
cd UniFi_Loco_Patch && shasum -a 256 -c checksums.txt
```

Si preferís no versionar el binario, `scripts/download-ufiber-configurator.sh` lo descarga
desde el release upstream y valida el checksum.

## Licencia

Código original (scripts y documentación): **MIT** — ver [`LICENSE`](LICENSE).
El binario de terceros `UFiber.Configurator` y sus `.dylib` conservan la licencia de su
proyecto upstream; no están cubiertos por la MIT de este repo.
