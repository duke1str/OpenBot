#!/usr/bin/env bash
set -Eeuo pipefail

. "$(dirname "$0")/require-bash.sh"

ROOT="$(cd "$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail(){ printf '\nFAILED: %s\n' "$*" >&2; exit 1; }
pass(){ printf '%s\n' "$*"; }

echo
echo "== VERIFY OPENBOT CUA GOVERNANCE =="

grep -Eq '^OPENBOT_CUA_ENABLED=(true|1|yes)$' .env \
  || fail "OPENBOT_CUA_ENABLED is not enabled in .env"

for skill in cua-browser-operator cua-desktop-operator; do
  grep -Fq "slug: $skill" examples/senior/skills.yaml \
    || fail "Senior package is missing skill: $skill"
done

grep -A30 -F -- "- id: senior" examples/senior/agents.yaml | grep -Fq -- "- cua-browser-operator" \
  || fail "Senior is missing the Cua browser skill"
grep -A30 -F -- "- id: senior" examples/senior/agents.yaml | grep -Fq -- "- cua-desktop-operator" \
  || fail "Senior is missing the Cua desktop skill"

for agent in morrow-grain ads-senior luna-kk publishing-growth; do
  grep -A30 -F -- "- id: $agent" examples/senior/agents.yaml | grep -Fq -- "- cua-browser-operator" \
    || fail "$agent is missing the Cua browser skill"
done

if grep -A30 -F -- "- id: pure-profit-health" examples/senior/agents.yaml | grep -Fq -- "cua-"; then
  fail "PP Senior must not receive Cua execution skills"
fi

SERVER_LOG="$ROOT/.logs/server.log"
[ -f "$SERVER_LOG" ] || fail "OpenBot server log is missing: $SERVER_LOG"
grep -Fq '"type":"cua-ready"' "$SERVER_LOG" \
  || {
    grep -F '"type":"cua-unavailable"' "$SERVER_LOG" | tail -1 >&2 || true
    fail "OpenBot did not confirm governed Cua connector bootstrap"
  }

LAST_READY="$(grep -F '"type":"cua-ready"' "$SERVER_LOG" | tail -1)"
printf '%s' "$LAST_READY" | grep -Fq '"pure-profit-health"' \
  && fail "PP Senior unexpectedly appears in Cua browser grants"

pass "OpenBot Cua connector bootstrap: PASS"
pass "Cua skill assignments: PASS"
pass "PP Senior Cua execution boundary: PASS"
echo
echo "OPENBOT CUA GOVERNANCE = PASS"
