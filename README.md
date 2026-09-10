# deapman

Gestor local de AppImages con deduplicación por contenido. Sin root, sin `/opt`, sin daemon: todo bajo `$HOME`. Instalación directa vía cargador empaquetado y adelgazamiento por symlinks a un store compartido.

Fork independiente de [ivan-hc/AM](https://github.com/ivan-hc/AM) v10.5 (GPL-3.0-or-later, licencia conservada en `LICENSE`); reescrito a local-first con núcleo en Zig.

## Instalar

```sh
sh install.sh            # --prefix ~/.local, sin root, idempotente
```

Requiere `zig` solo si quieres recompilar `deapman-thin` (`cd deapman-thin && zig build`).

## Arch Linux

Probado en x86_64 con glibc del sistema (los AppImages anylinux traen su propio
loader, así que en Arch van incluso mejor que en musl). Requisitos:

```sh
sudo pacman -S fuse3 fuse2 curl base-devel   # fuse2 solo para AppImages type-2 viejos
```

Luego clona e instala igual que arriba. Para `deapman-thin` tienes dos vías:

```sh
sudo pacman -S zig && cd deapman-thin && zig build   # recompilar (recomendado)
# o copia el binario estático de otra máquina (musl-estático, corre en glibc):
# install.sh lo recoge solo si está en deapman-thin/zig-out/bin/deapman-thin
```

`~/.local/bin` debe estar en tu `PATH` (install.sh avisa si no).

## Uso

```sh
deapman install <ruta|url> <nombre> [apodo]
deapman <nombre|apodo> [args...]   # = deapman run …
deapman dedup [-s] [nombre…]       # inventario + adelgazamiento a common/
deapman verify <nombre>            # magia AppImage + sha256 + shim
deapman gc [--aggressive]          # blobs huérfanos + staging
deapman list/info/remove/update
dpm …                              # alias corto, mismo binario
```

## Cómo funciona el dedup

Cada app conserva su original intacto (`originals/<n>/app.orig.AppImage`). `dedup -s` extrae a staging, mueve cada fichero byte-idéntico (sha256, ≥32 KiB) ya visto en otra app al store `common/<hh>/<sha>`, lo sustituye por un symlink absoluto y reempaqueta (appimagetool pkgforge + DwarFS/uruntime). Solo se fusiona contenido idéntico; mismo nombre con distinto hash jamás se mezcla.

Nunca se adelgazan lanzables (`AppRun*`, `sharun*`, `bin/*`, `sbin/*`, `usr/bin/*`, ejecutables `+x` no-`.so*`, `*.desktop`, iconos, `ld-linux*`, hooks…): un binario puede autolocalizar recursos vía `/proc/self/exe` (JVM, Qt, Electron) y romperse fuera de su árbol. Solo librerías y datos.

## Estructura

```
deapman            # dispatcher CLI (+ alias dpm vía argv[0])
modules/           # deapman.am (gestor) + deapman-dedup.am (inventory/thin)
deapman-thin/      # helper Zig: inventory, verify
tests/             # sh tests/run-tests.sh (suite offline)
install.sh / uninstall.sh
DEAPMAN.md         # especificación detallada
```

## Tests

```sh
sh tests/run-tests.sh
```

## Licencia

GPL-3.0-or-later (`LICENSE`). Fork de ivan-hc/AM, que mantiene su copyright; cambios propios © SrDicov.
