#!/usr/bin/env bash
# common.sh — logging, error handling, and small shared helpers.
# Sourced by the winunattend entrypoint; not meant to be run directly.

# ---- terminal colors (disabled when not a tty or NO_COLOR is set) -----------
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _c_reset=$'\033[0m'; _c_red=$'\033[31m'; _c_grn=$'\033[32m'
  _c_yel=$'\033[33m'; _c_blu=$'\033[34m'; _c_dim=$'\033[2m'; _c_bold=$'\033[1m'
else
  _c_reset=''; _c_red=''; _c_grn=''; _c_yel=''; _c_blu=''; _c_dim=''; _c_bold=''
fi

log()   { printf '%s==>%s %s\n'  "$_c_blu$_c_bold" "$_c_reset" "$*" >&2; }
info()  { printf '    %s\n' "$*" >&2; }
ok()    { printf '%s  ✓%s %s\n' "$_c_grn" "$_c_reset" "$*" >&2; }
warn()  { printf '%s  ! %s%s\n' "$_c_yel" "$*" "$_c_reset" >&2; }
err()   { printf '%serror:%s %s\n' "$_c_red$_c_bold" "$_c_reset" "$*" >&2; }
dim()   { printf '%s%s%s\n' "$_c_dim" "$*" "$_c_reset" >&2; }

die() { err "$*"; exit 1; }

# Ask a yes/no question. Honors $ASSUME_YES (set by --yes / non-interactive).
confirm() {
  local prompt="${1:-Continue?}"
  if [[ "${ASSUME_YES:-0}" == 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then
    die "non-interactive shell and --yes not given; refusing to assume yes for: $prompt"
  fi
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# Human-readable byte size (portable, integer math only).
human_size() {
  local bytes="${1:-0}" unit=B
  for u in KB MB GB TB; do
    (( bytes < 1024 )) && break
    bytes=$(( bytes / 1024 )); unit=$u
  done
  printf '%d%s' "$bytes" "$unit"
}

# File size in bytes, macOS/BSD stat with a GNU fallback.
file_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}
