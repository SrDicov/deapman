#!/bin/sh
# uninstall.sh — revierte `sh install.sh` (idempotente, sin root).
# Borra $PREFIX/share/deapman/dist/ y los symlinks $PREFIX/bin/deapman|dpm|modules.
# NUNCA toca datos ($HOME/.local/share/deapman: apps, originals, common…)
# ni configs ($HOME/.config/deapman): solo se elimina el subdir dist/.
# Uso: sh uninstall.sh [--prefix ~/.local]
# Nota: los "~" en patrones case son literales del usuario, no expansión.
# shellcheck disable=SC2088
set -eu

usage() {
	cat <<EOF
Uso: sh uninstall.sh [--prefix DIR] [--help]

Revierte install.sh: borra \$PREFIX/share/deapman/dist/ y los
symlinks \$PREFIX/bin/deapman, \$PREFIX/bin/dpm y \$PREFIX/bin/modules.
No toca datos ni configs (solo se elimina el subdir dist/).

Opciones:
  --prefix DIR    prefijo usado al instalar (defecto: ~/.local)
  --prefix=DIR    misma forma con =
  -h, --help      esta ayuda
EOF
}

PREFIX="${HOME:-$HOME}/.local"
while [ "$#" -gt 0 ]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		--prefix) [ "$#" -ge 2 ] || { echo "uninstall.sh: --prefix necesita un DIR" >&2; exit 2; }
			PREFIX="$2"; shift 2 ;;
		--prefix=*) PREFIX="${1#--prefix=}"; shift ;;
		--) shift; break ;;
		-*) echo "uninstall.sh: opción desconocida: $1 (usa --help)" >&2; exit 2 ;;
		*) echo "uninstall.sh: argumento inesperado: $1 (usa --help)" >&2; exit 2 ;;
	esac
done
[ -n "$PREFIX" ] || { echo "uninstall.sh: --prefix vacío" >&2; exit 2; }
case "$PREFIX" in
	~) PREFIX="$HOME" ;;
	"~/"*) PREFIX="$HOME/${PREFIX#~/}" ;;
esac
case "$PREFIX" in
	/*) ;;
	*) echo "uninstall.sh: --prefix debe ser absoluto: $PREFIX" >&2; exit 2 ;;
esac

DIST="$PREFIX/share/deapman/dist"
BIN="$PREFIX/bin"

for link in "$BIN/deapman" "$BIN/dpm" "$BIN/modules"; do
	if [ -L "$link" ]; then
		rm -f "$link"
		printf 'quitado symlink %s\n' "$link"
	elif [ -e "$link" ]; then
		printf 'AVISO: %s no es symlink, lo dejo intacto\n' "$link"
	else
		printf 'ausente (ok): %s\n' "$link"
	fi
done

if [ -e "$DIST" ]; then
	rm -rf "$DIST"
	printf 'borrado %s\n' "$DIST"
else
	printf 'ausente (ok): %s\n' "$DIST"
fi

printf 'datos y configs intactos (no se tocan $HOME/.local/share/deapman ni $HOME/.config/deapman)\n'
