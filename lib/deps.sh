#!/usr/bin/env bash
# deps.sh — dependency detection and installation (macOS / Homebrew).
# Sourced by the winunattend entrypoint.

# winunattend needs:
#   xorriso  — read/rewrite the bootable ISO (brew install xorriso)
#   hdiutil  — mount ISOs (ships with macOS)
# Optional:
#   qemu     — boot-test the produced ISO (brew install qemu)

deps_have_brew() { command -v brew >/dev/null 2>&1; }

# Ensure xorriso is available. With $INSTALL_DEPS=1 (or interactive consent)
# it will `brew install xorriso`; otherwise it prints instructions and exits.
deps_ensure() {
  if command -v xorriso >/dev/null 2>&1; then
    return 0
  fi

  warn "xorriso is not installed (required to rebuild the ISO)."

  if ! deps_have_brew; then
    err "Homebrew is not installed."
    info "Install Homebrew from https://brew.sh then run:"
    info "    brew install xorriso"
    exit 1
  fi

  if [[ "${INSTALL_DEPS:-0}" == 1 ]] || confirm "Install xorriso with Homebrew now?"; then
    log "Installing xorriso via Homebrew…"
    brew install xorriso || die "brew install xorriso failed"
    command -v xorriso >/dev/null 2>&1 || die "xorriso still not found after install"
    ok "xorriso installed."
  else
    info "Install it yourself with:  brew install xorriso"
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
