#!/usr/bin/env bash
# wim.sh — split an oversized install.wim/.esd so no file exceeds the ISO 9660
# single-file limit (~4 GiB). Windows Setup natively understands the resulting
# install.swm / install2.swm / … parts.
# Sourced by the winunattend entrypoint.

# ISO 9660 caps a single file extent at 4 GiB - 1. We keep parts a bit under
# that (and under FAT32's 4 GiB limit too, so WinDiskWriter needs no re-split).
WIM_LIMIT_BYTES=$(( 4 * 1024 * 1024 * 1024 ))   # 4 GiB — split anything larger
WIM_CHUNK_MIB="${WIM_CHUNK_MIB:-3800}"          # ~3.71 GiB parts

# Split image file $1 (e.g. .../sources/install.wim, may be on a read-only
# mount) into <base>.swm parts written next to $2. Does NOT delete the source.
wim_split_one() {
  local img=$1 swmbase=$2 log
  log=$(mktemp)
  info "splitting $(basename "$img") → $(basename "$swmbase") parts (<${WIM_CHUNK_MIB} MiB each)…"
  if ! wimlib-imagex split "$img" "$swmbase" "$WIM_CHUNK_MIB" >"$log" 2>&1; then
    cat "$log" >&2; rm -f "$log"
    die "wimlib-imagex split failed for $img"
  fi
  rm -f "$log"
}

# Split sources/install.wim and sources/install.esd in $1 (staging dir) if they
# exceed the ISO limit. Honors $NO_SPLIT (then it only warns).
wim_split_if_needed() {
  local stage=$1 img base size
  for base in install.wim install.esd; do
    img="$stage/sources/$base"
    [[ -f "$img" ]] || continue
    size=$(file_size "$img")
    (( size > WIM_LIMIT_BYTES )) || continue
    if [[ "${NO_SPLIT:-0}" == 1 ]]; then
      warn "$base is $(human_size "$size") (> 4 GiB) and --no-split was given;"
      warn "the output ISO may be unreadable by Windows Setup / on FAT32 USB."
      continue
    fi
    # install.wim → install.swm ; install.esd → install.swm as well (Setup looks
    # for install.swm regardless of the original container's extension).
    wim_split_one "$img" "$stage/sources/install.swm"
    rm -f "$img"
  done
}
