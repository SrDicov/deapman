# deapman — gestor local de AppImages con dedup por contenido

Fork local-only de [ivan-hc/AM](https://github.com/ivan-hc/AM) (APP-MANAGER 10.5,
GPL-3.0-or-later; el fork mantiene la licencia) + núcleo `deapman-thin` en Zig +
módulos nativos `modules/deapman.am` y `modules/deapman-dedup.am`. Sin root, sin `/opt`, todo bajo `$HOME`.

Repo independiente (sin remoto upstream; el historial conserva el punto de fork).
No se sigue su DB de programas salvo fallback de lectura (deapman es local-first:
tus AppImages + apodos).

## Layout

```
~/.local/share/deapman/
  originals/<nombre>/app.orig.AppImage  # original intacto, a-w (rollback + re-thin)
  apps/<nombre>/
    manifest                            # shell-sourcable (formato Altore), a-w
    app.thin.AppImage                   # solo si pasó por `dedup`
  common/<hh>/<sha256>                  # blobs deduplicados, a-w (solo gc escribe)
  inventory.tsv                         # app<TAB>path<TAB>size<TAB>sha (generado por dedup)
  cache/                                # descargas (TTL 7 días; --aggressive la vacía)
  tmp/                                  # staging (mismo FS; se limpia en cada gc)
~/.local/bin/<nombre|apodo>             # shims → `deapman run <nombre>`
~/.local/share/applications/<n>-deapman.desktop
~/.config/deapman/deapman-config                # fichero con el dir de apps (heredado de AppMan)
```

Instalado (`sh install.sh`, defecto `--prefix ~/.local`):

```
$PREFIX/share/deapman/dist/deapman        # script (su dirname es el DIR del fallback)
$PREFIX/share/deapman/dist/modules/*.am   # módulos junto al script (`_use_module` cae a `$DIR/modules`)
$PREFIX/share/deapman/dist/deapman-thin   # backend Zig, solo si estaba compilado
$PREFIX/bin/deapman, $PREFIX/bin/dpm      # symlinks → `../share/deapman/dist/deapman`
$PREFIX/bin/modules                       # symlink → `../share/deapman/dist/modules`
```

`$BIN/modules` es necesario: `_use_module` calcula `DIR` como dirname textual de
`$0` (sin resolver symlinks), así que vía `$BIN/deapman` el fallback
`$DIR/modules` solo acierta si `modules` vive junto al symlink.

## Instalación

```
sh install.sh [--prefix ~/.local]    # sin root, idempotente; instala thin si está compilado
sh uninstall.sh [--prefix ~/.local]  # borra dist/ + symlinks; jamás toca datos ni configs
```

Ambos aceptan `--prefix DIR` o `--prefix=DIR` (absoluto) y `--help`.

## Nombres

`deapman` (principal) y `dpm` (alias corto): mismo binario (`CLI` = argv[0];
`deapman -v` y `dpm -v` responden lo mismo). `deapman-thin` es el helper Zig
no interactivo (`inventory`, `verify`; `thin|gc` nativos pendientes).

`manifest` (shell, sin `jq` en cliente):

```
name='x' nick='y' version='…' origin='<ruta|url>' mode='orig|symlink|wrapper'
thin='0|1' sha_orig='…' updated='YYYY-MM-DD' refs='<hash…>'(lo puebla dedup)
```

## CLI

```
deapman install <ruta|url> <nombre> [apodo]  # nativo; sin 2º arg → delega a install.am (DB)
deapman <nombre|apodo> [args...] / deapman run … # ejecuta (atajo como `alt PKG`)
deapman update [nombre|apodo [nuevo]]        # sin nombre = nativas + resto vía _use_update
deapman dedup|thin [-s] [nombre…]            # inventario + repack symlink a common/ (-w pendiente)
deapman verify <nombre>                      # magia + sha256 + shim
deapman gc [--aggressive]                    # huérfanos por refcount + tmp; agresivo vacía caché
deapman list/info/remove                     # nativas primero, resto delegado a módulos upstream
```

Códigos: `0` ok · `1` operativo · `2` uso · `3` sin resultados · `4` red/hash.

## Reglas de seguridad (no negociables)

- Solo dedup de ficheros **byte-idénticos** (mismo sha256); mismo nombre con
  distinto hash jamás se fusiona. Umbral 32 KiB.
- Excluidos siempre: `AppRun*`, `sharun*`, `*.desktop`, iconos, `ld-linux*`,
  `lib.path`, `.env`, hooks, `bin/*`, `sbin/*`, `usr/bin/*`, `usr/sbin/*`,
  `*.exe` y todo ejecutable con bit `+x` que no sea librería (`.so*`): un
  binario lanzable puede autolocalizar recursos vía `/proc/self/exe` (JVM, Qt,
  Electron…) y romperse al resolverse dentro de `common/`.
- Original intacto siempre; reemplazo atómico + `verify` antes de sustituir.
- `gc` nunca toca apps instaladas ni `~/.config`/`~/.cache` de apps ni nada
  fuera de `DEAPMAN_HOME` (+ cachés propias de AM). Jamás `drop_caches` del sistema.

## Contrato del backend thin

- Original intacto: `app.orig.AppImage` (a-w) es rollback y fuente de re-thin;
  `update` resetea `thin='0'` y avisa de re-adelgazar; `verify` compara `sha_orig`.
- Solo fusión byte-idéntica (mismo sha256); mismo nombre con distinto hash jamás
  fusiona. Umbral 32 KiB (`DEAPMAN_MIN_THIN_BYTES`).
- Exclusiones (`_deapman_excluded` en `deapman-dedup.am`): `AppRun*`, `sharun*`,
  `*.desktop`, iconos (`*.png|*.svg|*.xpm`, `.DirIcon`), `*ld-linux*`, `lib.path`,
  `.env`, `*.hook|*.env`, `bin/*`, `sbin/*`, `usr/bin/*`, `usr/sbin/*`, `*.exe|*.EXE`,
  más ejecutables `+x` no-`.so*`.
- `dedup` puebla `refs='<sha…>'` en el manifest; `gc` borra por refcount solo
  blobs sin refs, más `tmp/` y caché (por TTL; toda con `--aggressive`).
- Estado: repack `-s` (symlinks a `common/`) implementado y verificado en 123
  apps reales (p. ej. qt_creator −73%, antigravity −25%, vscode −16%);
  `-w` (wrapper+library-path) pendiente.

## Hitos

1. ✅ Base: fork local-only, módulos nativos, install/run/list/info/remove/update/verify/gc, `deapman-thin inventory|verify`, `install.sh`/`uninstall.sh`, suite 29 pruebas.
2. ✅ Repack `dedup -s` verificado en 123 apps reales + regla anti-lanzables (bug JVM/simplex).
3. Siguiente: repack `-w` (wrapper+library-path, solo sharun conocido), updates URL/zsync, `deapman-thin thin|gc` nativos.
