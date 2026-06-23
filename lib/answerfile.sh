#!/usr/bin/env bash
# answerfile.sh — produce / sanitize the autounattend.xml that gets injected.
# Sourced by the winunattend entrypoint.

# Strip a leading UTF-8 BOM (EF BB BF) if present. Windows Setup fails to parse
# an answer file that starts with a BOM. Portable (no GNU sed needed).
answerfile_strip_bom() {
  local src=$1 dst=$2
  if [[ "$(head -c3 "$src" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == "efbbbf" ]]; then
    warn "input answer file had a UTF-8 BOM; stripping it."
    tail -c +4 "$src" > "$dst"
  else
    cp "$src" "$dst"
  fi
}

# Light validation: must look like a Windows unattend XML.
answerfile_validate() {
  local f=$1
  [[ -s "$f" ]] || die "answer file is empty: $f"
  grep -qa '<unattend' "$f" || die "answer file does not contain <unattend>: $f"
  grep -qa 'urn:schemas-microsoft-com:unattend' "$f" \
    || warn "answer file is missing the standard unattend namespace; Setup may ignore it."
  # If macOS has xmllint (it does), confirm it is well-formed XML.
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$f" 2>/dev/null || die "answer file is not well-formed XML: $f"
  fi
}

# Build the built-in default answer file at $1 by substituting placeholders.
# Reads globals: ARCH, UILANG, INPUTLOCALE, BYPASS_HW, TEMPLATE_FILE
answerfile_build_default() {
  local dst=$1
  [[ -f "$TEMPLATE_FILE" ]] || die "default template not found: $TEMPLATE_FILE"

  local tmp; tmp=$(mktemp)
  # Substitute placeholders. Values are simple tokens (no sed metachars).
  sed -e "s/@@ARCH@@/$ARCH/g" \
      -e "s/@@UILANG@@/$UILANG/g" \
      -e "s|@@INPUTLOCALE@@|$INPUTLOCALE|g" \
      "$TEMPLATE_FILE" > "$tmp"

  # Optionally drop the hardware-bypass block (inclusive of its markers).
  if [[ "${BYPASS_HW:-1}" != 1 ]]; then
    awk '
      /BYPASS_HW_START/ {skip=1}
      skip==0 {print}
      /BYPASS_HW_END/   {skip=0}
    ' "$tmp" > "$tmp.nohw" && mv "$tmp.nohw" "$tmp"
  fi

  # Windows answer files conventionally use CRLF; normalize to be safe.
  awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$tmp" > "$dst"
  rm -f "$tmp"

  answerfile_validate "$dst"
}

# Resolve the answer file to inject. With --autounattend it sanitizes and uses
# the user's file; otherwise it generates the built-in default. Writes the
# final file to $1 (caller-owned path).
# Reads globals: USER_XML (may be empty) plus the default-template globals.
answerfile_resolve() {
  local dst=$1

  if [[ -n "${USER_XML:-}" ]]; then
    [[ -f "$USER_XML" ]] || die "answer file not found: $USER_XML"
    log "Using your answer file: $USER_XML"
    answerfile_strip_bom "$USER_XML" "$dst"
    answerfile_validate "$dst"
  else
    log "Generating default answer file (bypass Microsoft account + hardware checks)."
    answerfile_build_default "$dst"
  fi
}
