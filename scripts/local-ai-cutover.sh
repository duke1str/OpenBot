#!/usr/bin/env bash
set -Eeuo pipefail

MODEL="SparkLLM/Spark-X2.5-4B"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say(){ printf '\n== %s ==\n' "$*"; }
fail(){ printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

say "SENIOR / Spark-X2.5-4B local cutover"

command -v curl >/dev/null 2>&1 || fail "curl missing"
command -v docker >/dev/null 2>&1 || fail "Docker missing"
OLLAMA_BIN="$(command -v ollama || true)"
[[ -n "$OLLAMA_BIN" ]] || fail "Ollama is not on PATH. Reopen Git Bash once, then rerun this script."
echo "Ollama: $OLLAMA_BIN"

if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  say "Starting Ollama"
  nohup "$OLLAMA_BIN" serve > "$HOME/ollama-serve.log" 2>&1 &
  for _ in {1..30}; do
    curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || {
  tail -n 80 "$HOME/ollama-serve.log" 2>/dev/null || true
  fail "Ollama server did not start"
}
echo "Ollama server: READY"

say "Downloading Spark-X2.5-4B"
"$OLLAMA_BIN" pull "$MODEL"

say "Testing Spark"
TEST_JSON="$(curl -fsS --max-time 300 http://127.0.0.1:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: SENIOR SPARK READY\"}],\"stream\":false}")" || fail "Spark inference test failed"
printf '%s\n' "$TEST_JSON" | grep -q 'SENIOR SPARK READY' || fail "Spark responded but acceptance phrase was missing"
echo "Spark inference: PASS"

[[ -f .env ]] || fail ".env not found"
BACKUP=".env.pre-spark.$(date +%Y%m%d-%H%M%S).bak"
cp .env "$BACKUP"

setenv(){
  local key="$1" value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '\n%s=%s\n' "$key" "$value" >> .env
  fi
}

say "Routing Senior/OpenBot to local Spark"
setenv OPENAI_BASE_URL "http://127.0.0.1:11434/v1"
setenv OPENAI_CONTAINER_BASE_URL "http://host.docker.internal:11434/v1"
setenv OPENAI_API_KEY "ollama-local"
setenv BOT_PROVIDER "openai"
setenv BOT_MODEL "$MODEL"
setenv AGENT_BOT_MODEL "$MODEL"

say "Restarting OpenBot without deleting data"
bash scripts/stop.sh --keep-computers
bash scripts/start.sh

say "Verification"
curl -fsS --max-time 8 http://127.0.0.1:3001/api/copilotkit/info | grep -q '"licenseStatus"' || fail "OpenBot API health failed"
"$OLLAMA_BIN" list | grep -F 'Spark-X2.5-4B' >/dev/null || fail "Spark model missing after restart"

echo
echo "SENIOR SPARK CUTOVER = PASS"
echo "OpenBot: http://localhost:3010"
echo "Senior:  http://localhost:3010/bot"
echo "Backup:  $BACKUP"
