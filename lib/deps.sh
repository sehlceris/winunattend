#!/usr/bin/env bash
# deps.sh — dependency detection and installation (macOS / Homebrew).
# Sourced by the winunattend entrypoint.

# winunattend needs (Homebrew formula → command):
#   xorriso  → xorriso         author the bootable ISO
#   wimlib   → wimlib-imagex   split a >4 GiB install.wim
# Ships with macOS: hdiutil (mount ISOs), rsync.
# Optional: qemu — boot-test the produced ISO (brew install qemu).

# formula:command pairs we require
DEPS_REQUIRED=( "xorriso:xorriso" "wimlib:wimlib-imagex" )

deps_have_brew() { command -v brew >/dev/null 2>&1; }

# Ensure all required tools exist. With $INSTALL_DEPS=1 (or interactive consent)
# missing ones are installed via Homebrew; otherwise we print instructions and exit.
deps_ensure() {
  local missing=() pair formula cmd
  for pair in "${DEPS_REQUIRED[@]}"; do
    formula=${pair%%:*}; cmd=${pair##*:}
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$formula")
  done
  require_cmd hdiutil   # macOS built-in; bail clearly if somehow absent
  require_cmd rsync

  [[ ${#missing[@]} -eq 0 ]] && return 0

  warn "missing dependencies: ${missing[*]}"
  if ! deps_have_brew; then
    err "Homebrew is not installed."
    info "Install Homebrew from https://brew.sh then run:"
    info "    brew install ${missing[*]}"
    exit 1
  fi

  if [[ "${INSTALL_DEPS:-0}" == 1 ]] || confirm "Install ${missing[*]} with Homebrew now?"; then
    log "Installing ${missing[*]} via Homebrew…"
    brew install "${missing[@]}" || die "brew install failed"
    ok "dependencies installed."
  else
    info "Install them yourself with:  brew install ${missing[*]}"
    exit 1
  fi
}

# Best-effort path to a qemu system binary for the given arch (or empty).
deps_qemu_bin() {
  case "${1:-amd64}" in
    amd64|x64|x86_64) command -v qemu-system-x86_64 ;;
    arm64|aarch64)    command -v qemu-system-aarch64 ;;
    *)                command -v qemu-system-x86_64 ;;
  esac
}
