#!/usr/bin/env bash
# iso.sh — read the source Windows ISO and rebuild it with the answer file.
# Sourced by the winunattend entrypoint.
#
# Why we fully extract + rebuild instead of editing in place:
#   Microsoft Windows ISOs keep ALL their content in a UDF filesystem; the
#   ISO 9660 side is just a stub README. xorriso can neither read that UDF tree
#   nor write UDF, so an in-place edit would drop the entire OS. We mount the
#   UDF via macOS (which reads it natively), copy the tree out, add the answer
#   file, split any >4 GiB install.wim, and author a fresh ISO 9660 + Joliet
#   image with the original El Torito BIOS + UEFI boot images.

# Echo the volume label of an ISO (e.g. CCCOMA_X64FRE_EN-US_DV9).
# NOTE: xorriso writes its informational output to stderr, so we merge it.
iso_get_volid() {
  local src=$1
  xorriso -indev "$src" -pvd_info 2>&1 \
    | awk -F"'" '/Volume id/ {print $2; exit}'
}

# Sanity-check the source: it must carry a dual BIOS + UEFI El Torito boot
# record. Warn (don't hard-fail) so unusual-but-valid media can still proceed.
iso_check_source() {
  local src=$1 et
  et=$(xorriso -indev "$src" -report_el_torito plain 2>&1)
  if ! grep -q 'Boot record  : El Torito' <<<"$et"; then
    warn "no El Torito boot record found in source — output may not be bootable."
    return 0
  fi
  grep -q 'BIOS' <<<"$et" || warn "no BIOS (legacy) boot image found in source."
  grep -q 'UEFI' <<<"$et" || warn "no UEFI boot image found in source."
}

# Mount an ISO read-only and echo its mount point.
iso_mount() {
  local src=$1 mnt
  mnt=$(hdiutil mount -readonly -nobrowse "$src" 2>/dev/null \
        | awk -F'\t' 'END{print $NF}')
  [[ -n "$mnt" && -d "$mnt" ]] || die "failed to mount $src"
  printf '%s' "$mnt"
}

iso_unmount() { [[ -n "${1:-}" ]] && hdiutil detach "$1" >/dev/null 2>&1 || true; }

# Copy the full tree from a mounted ISO ($1) into a staging dir ($2), excluding
# the big install images (handled separately so we don't copy then re-read 8 GB).
# Leaves the staged files writable.
iso_extract_tree() {
  local mnt=$1 stage=$2
  log "Copying Windows files out of the ISO…"
  rsync -rtH --no-perms --no-owner --no-group \
    --exclude '/sources/install.wim' --exclude '/sources/install.esd' \
    "$mnt"/ "$stage"/ || die "failed to copy ISO contents"
  chmod -R u+w "$stage"
}

# Author the output ISO from the staging dir.
#   $1 staging dir   $2 output path   $3 volume id   $4 UEFI boot image (rel path)
#
# El Torito layout mirrors Microsoft's oscdimg: a no-emul BIOS entry
# (boot/etfsboot.com) and a no-emul UEFI alt-boot entry. We deliberately do NOT
# pass -boot-info-table: that isolinux convention patches bytes into
# etfsboot.com and prevents it from executing. ISO level 3 enables the large
# files; Joliet carries the long Windows filenames.
#
# UEFI is the validated, primary boot path (and the only mode Windows 11 installs
# in). The BIOS entry is best-effort: modern Win11 cdboot resolves BOOTMGR from
# the UDF filesystem, which xorriso cannot author, so legacy-BIOS booting a
# rebuilt Win11 ISO may fail — install Windows 11 in UEFI mode.
iso_build() {
  local stage=$1 out=$2 volid=$3 efi_img=$4
  [[ -f "$stage/boot/etfsboot.com" ]] || die "missing boot/etfsboot.com in source tree."
  [[ -f "$stage/$efi_img" ]]          || die "missing UEFI boot image: $efi_img"
  log "Authoring bootable ISO (ISO 9660 + Joliet, UEFI + BIOS El Torito)…"
  xorriso -as mkisofs \
    -iso-level 3 \
    -volid "$volid" \
    -J -joliet-long -R \
    -b boot/etfsboot.com -no-emul-boot -boot-load-size 8 \
    -eltorito-alt-boot \
    -e "$efi_img" -no-emul-boot \
    -o "$out" "$stage" 2>&1 \
    | grep -viE '^xorriso : UPDATE|done, estimate|files added' || true
  local rc=${PIPESTATUS[0]}
  (( rc == 0 )) || die "xorriso failed (exit $rc)."
  [[ -s "$out" ]] || die "ISO authoring produced no output."
}

# Verify the produced ISO: required paths must exist inside it and it must carry
# a boot record. (The output is a full ISO 9660 tree, so xorriso can read it.)
iso_verify() {
  local out=$1; shift
  local ok=1 p
  for p in "$@"; do
    if xorriso -indev "$out" -find "$p" 2>&1 | grep -qx "'$p'"; then
      ok "present in ISO: $p"
    else
      err "missing from ISO: $p"; ok=0
    fi
  done
  if xorriso -indev "$out" -report_el_torito plain 2>&1 \
     | grep -q 'Boot record  : El Torito'; then
    ok "boot record preserved (BIOS + UEFI El Torito)."
  else
    err "boot record missing from output ISO."; ok=0
  fi
  [[ $ok == 1 ]]
}
