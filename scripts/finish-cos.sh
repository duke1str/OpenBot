#!/usr/bin/env bash
set -Eeuo pipefail

. "$(dirname "$0")/require-bash.sh"

ROOT="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say(){ printf '\n== %s ==\n' "$*"; }
fail(){ printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

say "COS CORE + KING + CUA"
bash scripts/finish-king.sh

say "PRIVATE PHONE ACCESS"
command -v powershell.exe >/dev/null 2>&1 || fail "PowerShell is required for Tailscale phone setup."
PHONE_SETUP="$ROOT/scripts/setup-senior-phone.ps1"
if command -v cygpath >/dev/null 2>&1; then
  PHONE_SETUP="$(cygpath -w "$PHONE_SETUP")"
fi
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PHONE_SETUP" || fail "Senior phone access setup did not complete."

echo
echo "========================================"
echo "COS SENIOR WORKSTATION BUILD = READY FOR FINAL HUMAN ACCEPTANCE"
echo "========================================"
echo "Verified by this script:"
echo "  KING Spark local inference"
echo "  OpenBot six-agent runtime route"
echo "  bounded Cua browser runtime"
echo "  bounded Cua desktop runtime"
echo "  governed OpenBot Cua grants"
echo "  PP Senior excluded from Cua execution"
echo "  private Tailscale Serve configured"
echo
echo "Still requires human acceptance:"
echo "  open Senior from the phone URL and send one command"
echo "  run one harmless bounded browser read through Senior"
echo "  confirm the laptop remains awake while unattended"
