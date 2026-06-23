#!/usr/bin/env bash
# iso.sh — read the source Windows ISO and rebuild it with the answer file.
# Sourced by the winunattend entrypoint.

# Echo the volume label of an ISO (e.g. CCCOMA_X64FRE_EN-US_DV9).
iso_get_volid() {
  local src=$1 vid
  vid=$(xorriso -indev "$src" -pvd_info 2>/dev/null \
        | awk -F"'" '/Volume id/ {print $2; exit}')
  printf '%s' "$vid"
}

# Confirm the source really is a Windows install ISO with a dual BIOS+UEFI
# El Torito boot record. Warn (don't hard-fail) so unusual-but-valid media
# can still be processed with --yes.
iso_check_source() {
  local src=$1
  local et
  et=$(xorriso -indev "$src" -report_el_torito plain 2>/dev/null)
  if ! grep -q 'Boot record  : El Torito' <<<"$et"; then
    warn "no El Torito boot record found in source — output may not be bootable."
    return 0
  fi
  grep -q 'BIOS' <<<"$et" || warn "no BIOS (legacy) boot image found in source."
  grep -q 'UEFI' <<<"$et" || warn "no UEFI boot image found in source."
  # Windows media has sources/install.{wim,esd}. Probe via the ISO directory.
  if ! xorriso -indev "$src" -find /sources -name 'install.*' 2>/dev/null \
       | grep -qiE 'install\.(wim|esd)'; then
    warn "could not find sources/install.wim|esd — is this really a Windows ISO?"
  fi
}

# Rebuild the ISO: copy the source 1:1 (boot payload included) and graft in the
# extra files. Trailing args are xorriso file ops, e.g.:
#     iso_repack SRC OUT VOLID -map /tmp/answer.xml /autounattend.xml
#
# `-boot_image any replay` reproduces the original El Torito / MBR / GPT boot
# structures byte-for-byte instead of recomputing them, which is what keeps a
# Windows ISO bootable on both BIOS and UEFI after modification.
iso_repack() {
  local src=$1 out=$2 volid=$3; shift 3
  log "Rebuilding ISO (this copies the full image; large ISOs take a few minutes)…"
  xorriso \
    -indev "$src" \
    -outdev "$out" \
    -boot_image any replay \
    -volid "$volid" \
    "$@" \
    -commit -end
}

# Verify the produced ISO: each given path must exist inside it, and it must
# still carry a boot record. Returns non-zero on failure.
iso_verify() {
  local out=$1; shift
  local ok=1 p
  for p in "$@"; do
    if xorriso -indev "$out" -find "$p" 2>/dev/null | grep -qx "'$p'"; then
      ok "present in ISO: $p"
    else
      err "missing from ISO: $p"; ok=0
    fi
  done
  if xorriso -indev "$out" -report_el_torito plain 2>/dev/null \
     | grep -q 'Boot record  : El Torito'; then
    ok "boot record preserved (El Torito)."
  else
    err "boot record missing from output ISO."; ok=0
  fi
  [[ $ok == 1 ]]
}
