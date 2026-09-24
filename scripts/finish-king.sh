#!/usr/bin/env bash
set -Eeuo pipefail

. "$(dirname "$0")/require-bash.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODEL="maternion/spark-x2.5:4b"
KING_MODELS_WIN='D:\SENIOR_AI\models'
KING_MODELS='/d/SENIOR_AI/models'
KING_LOGS='/d/SENIOR_AI/logs'

say(){ printf '\n== %s ==\n' "$*"; }
fail(){ printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

say "VERIFY KING"
[ -d "$KING_MODELS" ] || fail "KING model store is missing at $KING_MODELS_WIN"
mkdir -p "$KING_LOGS"
command -v ollama >/dev/null 2>&1 || fail "Ollama is not on PATH"
command -v curl >/dev/null 2>&1 || fail "curl is missing"
command -v docker >/dev/null 2>&1 || fail "Docker CLI is missing"

say "PIN OLLAMA TO KING"
# Persist for this Windows user. setx does not require an administrator for a user variable.
cmd.exe /c "setx OLLAMA_MODELS \"$KING_MODELS_WIN\"" >/dev/null 2>&1 ||   echo "WARNING: could not persist OLLAMA_MODELS with setx; continuing with this Bash session."
export OLLAMA_MODELS="$KING_MODELS_WIN"
export OLLAMA_HOST='127.0.0.1:11434'

# Ollama for Windows normally runs as the signed-in user. Stop only that executable; no elevation
# is requested. If it is already stopped, taskkill exits non-zero and we intentionally continue.
taskkill.exe /IM ollama.exe /F >/dev/null 2>&1 || true
sleep 2

say "START OLLAMA FROM KING"
nohup ollama serve >"$KING_LOGS/ollama-bash.log" 2>"$KING_LOGS/ollama-bash-error.log" &
for _ in $(seq 1 45); do
  curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 ||   fail "Ollama did not start. See D:\SENIOR_AI\logs\ollama-bash-error.log"

TAGS="$(curl -fsS --max-time 8 http://127.0.0.1:11434/api/tags)"
printf '%s' "$TAGS" | grep -Fq "$MODEL" || fail "KING Ollama does not see $MODEL"
echo "KING Ollama: READY"

say "PROVE KING SPARK INFERENCE"
BODY='{"model":"maternion/spark-x2.5:4b","messages":[{"role":"user","content":"Reply briefly with: KING BASH READY"}],"stream":false,"think":false,"options":{"num_ctx":8192,"num_predict":96}}'
RESPONSE="$(curl -fsS --max-time 180 http://127.0.0.1:11434/api/chat   -H 'Content-Type: application/json' -d "$BODY")" || fail "KING Spark inference failed"
printf '%s' "$RESPONSE" | grep -Fq 'KING BASH READY' || {
  printf '%s\n' "$RESPONSE" >"$KING_LOGS/king-bash-last-response.json"
  fail "Spark responded without the acceptance phrase; response saved to KING logs."
}
echo "KING Spark inference: PASS"

say "START OPENBOT FAST REFRESH"
OPENBOT_FORCE_RELOAD=true OPENBOT_SKIP_BUILD=true bash scripts/start.sh

say "VERIFY FULL KING ROUTE"
bash scripts/verify-king-stage2.sh

echo
echo "========================================"
echo "SENIOR KING FINAL INFRASTRUCTURE = PASS"
echo "========================================"
echo "Model:   $MODEL"
echo "Models:  $KING_MODELS_WIN"
echo "Senior:  http://localhost:3010/bot"
echo
echo "Next acceptance prompt:"
echo "Identify yourself and your command structure. List the project agents under your authority. State your operating rules, current boundaries, and what actions require my approval. Do not perform any external action."
