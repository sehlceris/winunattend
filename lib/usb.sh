#!/usr/bin/env bash
# usb.sh — detect removable USB drives and describe them, safely.
# Sourced by the winflash entrypoint.
#
# SAFETY: we only ever surface *whole, external, physical, removable* disks.
# Internal/system disks are filtered out at two layers (the `external physical`
# query AND a per-disk property re-check) so an interactive user can never pick
# their boot drive by mistake.

# Read one key from a `diskutil info -plist` blob passed on stdin.
# Booleans come back as the literal strings "true" / "false".
_usb_plist_get() { plutil -extract "$1" raw -o - - 2>/dev/null; }

# Echo the BSD identifiers (e.g. "disk4") of every attached drive that is a
# whole, external, physical, removable USB disk — one per line. Prints nothing
# if there are none. Never includes internal disks.
usb_list_disks() {
  local ids id info
  # `external physical` already excludes internal/synthesized disks; we still
  # re-verify each candidate's properties below as a second safety layer.
  ids=$(diskutil list -plist external physical 2>/dev/null \
        | plutil -extract WholeDisks json -o - - 2>/dev/null \
        | tr -d '[]" ' | tr ',' '\n')
  for id in $ids; do
    [[ -n "$id" ]] || continue
    info=$(diskutil info -plist "$id" 2>/dev/null) || continue
    [[ "$(_usb_plist_get Internal          <<<"$info")" == false    ]] || continue
    [[ "$(_usb_plist_get WholeDisk         <<<"$info")" == true     ]] || continue
    [[ "$(_usb_plist_get VirtualOrPhysical <<<"$info")" == Physical ]] || continue
    [[ "$(_usb_plist_get WritableMedia     <<<"$info")" == true     ]] || continue
    # Genuinely removable media: ejectable, flagged removable, or on the USB bus.
    if [[ "$(_usb_plist_get Ejectable      <<<"$info")" == true \
       || "$(_usb_plist_get RemovableMedia <<<"$info")" == true \
       || "$(_usb_plist_get BusProtocol    <<<"$info")" == USB ]]; then
      printf '%s\n' "$id"
    fi
  done
}

# Echo a one-line human description of a disk: "<media> — <size> (<bus>, <label>)".
usb_describe() {
  local id=$1 info name size bus label
  info=$(diskutil info -plist "$id" 2>/dev/null) || { printf '%s' "$id"; return; }
  name=$(_usb_plist_get IORegistryEntryName <<<"$info")
  [[ -n "$name" ]] || name=$(_usb_plist_get MediaName <<<"$info")
  size=$(_usb_plist_get Size <<<"$info")
  bus=$(_usb_plist_get BusProtocol <<<"$info")
  label=$(_usb_plist_get VolumeName <<<"$info")
  printf '%s — %s (%s' "$name" "$(human_size "${size:-0}")" "${bus:-?}"
  [[ -n "$label" ]] && printf ', “%s”' "$label"
  printf ')'
}

# Echo a disk's total size in bytes.
usb_disk_size() {
  diskutil info -plist "$1" 2>/dev/null | _usb_plist_get Size
}
