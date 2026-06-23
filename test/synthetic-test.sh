#!/usr/bin/env bash
#
# synthetic-test.sh — exercise the winunattend pipeline end-to-end WITHOUT a real
# Windows ISO. It fabricates a Windows-shaped UDF+ISO9660 source image (dummy
# boot files, a small sources/install.wim), runs winunattend on it, and asserts
# the output ISO mounts and contains the answer file + the expected tree.
#
# This validates mount → extract → answer-file injection → ISO authoring →
# verification. The >4 GiB WIM-split path is covered by testing against a real
# Windows ISO (see README), since it needs a genuine multi-gigabyte WIM.
#
# Requires: xorriso, wimlib, hdiutil (macOS). Run:  test/synthetic-test.sh
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/winunattend-test.XXXXXX")
trap 'hdiutil detach "$TMP/mnt" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

pass=0; fail=0
check() { # check "desc" condition...
  local d=$1; shift
  if "$@"; then printf '  ✓ %s\n' "$d"; pass=$((pass+1))
  else printf '  ✗ %s\n' "$d"; fail=$((fail+1)); fi
}

echo "==> Building a fake Windows-shaped source ISO"
TREE="$TMP/tree"
mkdir -p "$TREE"/{boot,efi/boot,efi/microsoft/boot,sources}
printf 'ETFSBOOT-STUB' > "$TREE/boot/etfsboot.com"
head -c 1048576 /dev/zero > "$TREE/efi/microsoft/boot/efisys.bin"
head -c 1048576 /dev/zero > "$TREE/efi/microsoft/boot/efisys_noprompt.bin"
printf 'BOOTX64-STUB' > "$TREE/efi/boot/bootx64.efi"
printf 'SETUP-STUB'   > "$TREE/setup.exe"
printf 'BOOTMGR-STUB' > "$TREE/bootmgr"
# a small but real WIM so the sources/ payload is representative
echo "hello from the fake install image" > "$TREE/sources/_payload.txt"
wimlib-imagex capture "$TREE/sources" "$TREE/sources/install.wim" \
  --compress=none >/dev/null 2>&1
rm -f "$TREE/sources/_payload.txt"
printf 'BOOTWIM-STUB' > "$TREE/sources/boot.wim"

SRC="$TMP/source.iso"
# UDF + ISO9660 hybrid, mimicking how Microsoft ships media
hdiutil makehybrid -quiet -udf -iso -default-volume-name TEST_WIN \
  -o "${SRC%.iso}" "$TREE"
[[ -f "$SRC" ]] || SRC="${SRC%.iso}.iso"

echo "==> Running winunattend on the fake ISO"
OUT="$TMP/out.iso"
"$ROOT/winunattend" -y -o "$OUT" "$SRC" || { echo "winunattend failed"; exit 1; }

echo "==> Verifying output"
check "output ISO exists and is non-empty" test -s "$OUT"
mkdir -p "$TMP/mnt"
M=$(hdiutil mount -readonly -nobrowse -mountpoint "$TMP/mnt" "$OUT" 2>/dev/null \
    | awk -F'\t' 'END{print $NF}')
check "output mounts"                       test -d "$M"
check "autounattend.xml at root"            test -f "$M/autounattend.xml"
check "autounattend has unattend element"   grep -q '<unattend' "$M/autounattend.xml"
check "boot/etfsboot.com carried over"      test -f "$M/boot/etfsboot.com"
check "efi/boot/bootx64.efi carried over"   test -f "$M/efi/boot/bootx64.efi"
check "sources/boot.wim carried over"       test -f "$M/sources/boot.wim"
check "sources/install.wim present"         test -f "$M/sources/install.wim"
hdiutil detach "$M" >/dev/null 2>&1 || true

check "output carries an El Torito record" bash -c \
  "xorriso -indev '$OUT' -report_el_torito plain 2>&1 | grep -q 'Boot record  : El Torito'"

echo
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
