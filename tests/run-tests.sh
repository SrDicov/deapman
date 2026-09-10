#!/bin/sh
# run-tests.sh — suite de deapman en HOME temporal; no toca el sistema ni la red.
# Uso: sh tests/run-tests.sh
set -u

HERE=$(dirname "$0")
ROOT=$(readlink -f "$HERE/.." 2>/dev/null || (cd "$HERE/.." && pwd))
DAP="$ROOT/deapman"
THIN="$ROOT/deapman-thin/zig-out/bin/deapman-thin"
PASS=0; FAIL=0

T=$(mktemp -d "${TMPDIR:-/tmp}/deapman-test.XXXXXX")
REALHOME="$HOME"
export HOME="$T/home" XDG_DATA_HOME="$T/xdg" XDG_CONFIG_HOME="$T/cfg"
export XDG_CACHE_HOME="$T/cache" XDG_BIN_HOME="$T/bin" DEAPMAN_HOME="$T/xdg/deapman"
export PATH="$T/bin:$PATH"
mkdir -p "$HOME" "$T/bin" "$XDG_CONFIG_HOME/deapman"
printf 'Applications\n' > "$XDG_CONFIG_HOME/deapman/deapman-config"

ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n%s\n' "$1" "${2:-}"; }
is_eq() {
	if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "  esperado: [$2]  obtenido: [$3]"; fi
}
contains() {
	case "$3" in *"$2"*) ok "$1";; *) bad "$1" "  no contiene [$2] en: $3";; esac
}

# 1. version + gc vacío
"$DAP" -v >/dev/null 2>&1 # primera ejecución (setup + completion)
out=$("$DAP" -v 2>/dev/null); is_eq "version" "0.1.0" "$out"
out=$("$DAP" gc 2>/dev/null); contains "gc vacío" "0 blobs" "$out"
out=$("$DAP" gc --aggressive 2>/dev/null); contains "gc agresivo" "agresivo" "$out"

# 2. install: usos inválidos
"$DAP" install >/dev/null 2>&1; is_eq "install sin args rc=2" "2" "$?"
"$DAP" install /no/existe demo >/dev/null 2>&1; is_eq "install ruta mala rc=1" "1" "$?"
printf 'no-elf' > "$T/fake.bin"
"$DAP" install "$T/fake.bin" demo >/dev/null 2>&1; is_eq "install no-appimage rc=1" "1" "$?"
"$DAP" install "$T/fake.bin" 'MAL NOMBRE' >/dev/null 2>&1; is_eq "install nombre malo rc=2" "2" "$?"

# 3. remove / verify / info de ausentes
"$DAP" verify nadie >/dev/null 2>&1; is_eq "verify ausente rc=3" "3" "$?"
"$DAP" info nadie >/dev/null 2>&1; is_eq "info ausente rc=3" "3" "$?"

# 4. atajo desconocido
"$DAP" zzz-noexiste >/dev/null 2>&1; is_eq "atajo desconocido rc=2" "2" "$?"

# 5. app nativa fabricada (sin AppImage real): list/info la ven, verify la rechaza
mkdir -p "$DEAPMAN_HOME/apps/fakedemo" "$DEAPMAN_HOME/originals/fakedemo"
printf 'not-an-appimage' > "$DEAPMAN_HOME/originals/fakedemo/app.orig.AppImage"
cat >"$DEAPMAN_HOME/apps/fakedemo/manifest" <<'EOF'
name='fakedemo'
nick='fd'
version='0'
origin='test'
mode='orig'
thin='0'
sha_orig='deadbeef'
updated='2026-09-08'
EOF
out=$("$DAP" list 2>/dev/null | head -3); contains "list ve nativa" "fakedemo (fd)" "$out"
out=$("$DAP" info fd 2>/dev/null); contains "info por apodo" "nombre:      fakedemo" "$out"
"$DAP" verify fakedemo >/dev/null 2>&1
[ "$?" -ne 0 ] && ok "verify detecta magia rota" || bad "verify detecta magia rota"
printf 'y\n' | "$DAP" remove fakedemo >/dev/null 2>&1; is_eq "remove nativa rc" "0" "$?"
[ -e "$DEAPMAN_HOME/apps/fakedemo" ] && bad "remove borra appdir" || ok "remove borra appdir"

# 6. E2E con AppImages reales pequeños del corpus (solo lectura, si existe)
REAL="$HOME/no-existe"; REAL2="$REAL"
for _c in /home/dicov/appimages-test/xclock-1.2.1-1-anylinux-x86_64.AppImage \
          /home/dicov/appimages-test/HP-15C-5.1.00-anylinux-x86_64.AppImage \
          "$REALHOME"/.local/share/deapman/originals/xclock-1.2.1-1-anylinux-x86_64/app.orig.AppImage \
          "$REALHOME"/.local/share/deapman/originals/hp-15c-5.1.00-anylinux-x86_64/app.orig.AppImage; do
	[ -f "$_c" ] || continue
	[ "$REAL" = "$HOME/no-existe" ] && REAL="$_c" || REAL2="$_c"
done
if [ -f "$REAL" ] && [ -f "$REAL2" ]; then
	"$DAP" install "$REAL" e2eclock clk >/dev/null 2>&1; is_eq "e2e install rc" "0" "$?"
	"$DAP" verify e2eclock >/dev/null 2>&1; is_eq "e2e verify rc" "0" "$?"
	out=$("$DAP" update e2eclock 2>&1); contains "e2e update al día" "al día" "$out"
	"$DAP" update e2eclock "$REAL2" >/dev/null 2>&1; is_eq "e2e update reemplazo rc" "0" "$?"
	out=$("$DAP" info clk 2>/dev/null); contains "e2e reemplazo registrado" "$REAL2" "$out"
	"$DAP" remove -f e2eclock >/dev/null 2>&1; is_eq "e2e remove rc" "0" "$?"
	[ -e "$DEAPMAN_HOME/apps/e2eclock" ] && bad "e2e appdir borrado" || ok "e2e appdir borrado"
else
	printf 'SKIP e2e (sin corpus en /home/dicov/appimages-test)\n'
fi

# 7. _deapman_excluded: lanzables nunca se adelgazan (JVM/Qt/Electron se
#    autolocalizan vía /proc/self/exe; las .so por mmap son seguras)
sed -n '/^_deapman_excluded()/,/^}/p' "$ROOT/modules/deapman-dedup.am" > "$T/excl.sh"
# shellcheck disable=SC1090
. "$T/excl.sh"
mkdir -p "$T/ex/bin" "$T/ex/lib"
printf 'x' > "$T/ex/bin/java"; chmod +x "$T/ex/bin/java"
printf 'x' > "$T/ex/lib/libfoo.so.1"; chmod +x "$T/ex/lib/libfoo.so.1"
printf 'x' > "$T/ex/lib/data.dat"
_deapman_excluded "bin/java" "$T/ex/bin/java" >/dev/null 2>&1
is_eq "excluye bin/ ejecutable" "0" "$?"
_deapman_excluded "lib/libfoo.so.1" "$T/ex/lib/libfoo.so.1" >/dev/null 2>&1
is_eq "no excluye .so con +x" "1" "$?"
_deapman_excluded "lib/data.dat" "$T/ex/lib/data.dat" >/dev/null 2>&1
is_eq "no excluye dato sin +x" "1" "$?"
printf '#!/bin/sh\n' > "$T/ex/lib/run.sh"; chmod +x "$T/ex/lib/run.sh"
_deapman_excluded "lib/run.sh" "$T/ex/lib/run.sh" >/dev/null 2>&1
is_eq "excluye script +x fuera de bin" "0" "$?"
unset -f _deapman_excluded

# 8. deapman-thin (si está compilado)
if [ -x "$THIN" ]; then
	mkdir -p "$T/w/sub"; printf 'hello' > "$T/w/a"; printf 'hello' > "$T/w/sub/b"; printf 'x' > "$T/w/c"
	n=$("$THIN" inventory w "$T/w" | wc -l | tr -d ' '); is_eq "thin inventory 3 ficheros" "3" "$n"
	"$THIN" verify "$T/w/a" 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 >/dev/null 2>&1
	is_eq "thin verify ok rc" "0" "$?"
	"$THIN" verify "$T/w/c" 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824 >/dev/null 2>&1
	is_eq "thin verify mismatch rc" "1" "$?"
else
	printf 'SKIP deapman-thin (sin compilar: cd deapman-thin && zig build)\n'
fi

rm -rf "$T"
printf '\n=== %d ok, %d fallos ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
