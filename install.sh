#!/bin/sh
# install.sh — instalador local de deapman (sin root, idempotente).
# Copia el script + módulos + backend thin a $PREFIX/share/deapman/dist/
# y crea los symlinks $PREFIX/bin/deapman, $PREFIX/bin/dpm y $PREFIX/bin/modules.
# Funciona instalado porque `_use_module` en `deapman` cae a $DIR/modules:
# dist/modules/ en invocación directa, $BIN/modules (symlink) vía los symlinks
# ($DIR es el dirname textual de $0, sin resolver symlinks).
# Uso: sh install.sh [--prefix ~/.local]
# Nota: los "~" en patrones case son literales del usuario, no expansión.
# shellcheck disable=SC2088
set -eu

usage() {
	cat <<EOF
Uso: sh install.sh [--prefix DIR] [--help]

Instala deapman sin root (idempotente, re-ejecutable):
  deapman                        -> \$PREFIX/share/deapman/dist/deapman
  modules/*.am                   -> \$PREFIX/share/deapman/dist/modules/
  deapman-thin (si está compilado) -> \$PREFIX/share/deapman/dist/deapman-thin
  symlinks \$PREFIX/bin/deapman y \$PREFIX/bin/dpm -> ../share/deapman/dist/deapman
  symlink  \$PREFIX/bin/modules -> ../share/deapman/dist/modules (fallback \$DIR/modules vía symlink)

Opciones:
  --prefix DIR    prefijo de instalación (defecto: ~/.local)
  --prefix=DIR    misma forma con =
  -h, --help      esta ayuda
EOF
}

PREFIX="${HOME:-$HOME}/.local"
while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		--prefix) [ "$#" -ge 2 ] || { echo "install.sh: --prefix necesita un DIR" >&2; exit 2; }
			PREFIX="$2"; shift 2 ;;
		--prefix=*) PREFIX="${1#--prefix=}"; shift ;;
		--) shift; break ;;
		-*) echo "install.sh: opción desconocida: $1 (usa --help)" >&2; exit 2 ;;
		*) echo "install.sh: argumento inesperado: $1 (usa --help)" >&2; exit 2 ;;
	esac
done
[ -n "$PREFIX" ] || { echo "install.sh: --prefix vacío" >&2; exit 2; }
case "$PREFIX" in
	~) PREFIX="$HOME" ;;
	"~/"*) PREFIX="$HOME/${PREFIX#~/}" ;;
esac
case "$PREFIX" in
	/*) ;;
	*) echo "install.sh: --prefix debe ser absoluto: $PREFIX" >&2; exit 2 ;;
esac

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
DIST="$PREFIX/share/deapman/dist"
BIN="$PREFIX/bin"

[ -f "$SRC_DIR/deapman" ] || { echo "install.sh: no existe $SRC_DIR/deapman (¿repo incompleto?)" >&2; exit 1; }
[ -d "$SRC_DIR/modules" ] || { echo "install.sh: no existe $SRC_DIR/modules/" >&2; exit 1; }

mkdir -p "$DIST/modules" "$BIN"

cp -f "$SRC_DIR/deapman" "$DIST/deapman"
chmod +x "$DIST/deapman"
cp -f "$SRC_DIR"/modules/*.am "$DIST/modules/"

if [ -x "$SRC_DIR/deapman-thin/zig-out/bin/deapman-thin" ]; then
	cp -f "$SRC_DIR/deapman-thin/zig-out/bin/deapman-thin" "$DIST/deapman-thin"
	chmod +x "$DIST/deapman-thin"
	THIN_MSG="thin backend instalado"
else
	THIN_MSG="AVISO: sin deapman-thin compilado (cd deapman-thin && zig build); sigo sin backend nativo"
fi

ln -sf ../share/deapman/dist/deapman "$BIN/deapman"
ln -sf ../share/deapman/dist/deapman "$BIN/dpm"
# El fallback de `_use_module` mira `$DIR/modules` con DIR=dirname textual de $0
# (sin resolver symlinks): vía $BIN/deapman, DIR es $BIN, así que se enlaza
# también $BIN/modules → dist/modules para que el instalado funcione sin red.
ln -sf ../share/deapman/dist/modules "$BIN/modules"

printf 'deapman instalado en %s\n' "$DIST"
printf '%s\n' "$THIN_MSG"
printf 'symlinks: %s/deapman, %s/dpm, %s/modules\n' "$BIN" "$BIN" "$BIN"
case ":$PATH:" in
	*":$BIN:"*) ;;
	*) printf 'AVISO: %s no está en PATH; añade: export PATH="%s:$PATH"\n' "$BIN" "$BIN" ;;
esac
