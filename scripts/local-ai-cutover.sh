#!/usr/bin/env bash
set -Eeuo pipefail

MODEL="maternion/spark-x2.5:4b"
HEAVY_MODEL="SparkLLM/Spark-X2.5-4B"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say(){ printf '\n== %s ==\n' "$*"; }
fail(){ printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

say "SENIOR / Spark-X2.5-4B Q4 local cutover"

command -v curl >/dev/null 2>&1 || fail "curl missing"
command -v docker >/dev/null 2>&1 || fail "Docker missing"
OLLAMA_BIN="$(command -v ollama || true)"
[[ -n "$OLLAMA_BIN" ]] || fail "Ollama is not on PATH. Reopen Git Bash once, then rerun this script."

if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  say "Starting Ollama"
  OLLAMA_CONTEXT_LENGTH=8192 nohup "$OLLAMA_BIN" serve > "$HOME/ollama-serve.log" 2>&1 &
  for _ in {1..30}; do
    curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
fi
curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 || fail "Ollama server did not start"
echo "Ollama server: READY"

# The official 4B Ollama artifact is BF16 (~8.2GB). On this 12GB Windows host it downloaded
# successfully but could not produce a first token in five minutes. Use the same 4.11B Spark-X2.5
# weights in Q4_K_M (~2.6GB), leaving enough RAM for Windows + Docker + OpenBot.
say "Downloading laptop-sized Spark-X2.5-4B Q4_K_M"
"$OLLAMA_BIN" pull "$MODEL"

say "Testing Spark"
TEST_JSON="$(curl -fsS --max-time 180 http://127.0.0.1:11434/api/chat \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: SENIOR SPARK READY\"}],\"stream\":false,\"options\":{\"num_ctx\":8192,\"num_predict\":32}}")" || fail "Q4 Spark inference test failed"
printf '%s\n' "$TEST_JSON" | grep -q 'SENIOR SPARK READY' || { printf '%s\n' "$TEST_JSON"; fail "Spark responded but acceptance phrase was missing"; }
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

say "Verifying"
curl -fsS --max-time 8 http://127.0.0.1:3001/api/copilotkit/info | grep -q '"licenseStatus"' || fail "OpenBot API health failed"
"$OLLAMA_BIN" list | grep -F 'maternion/spark-x2.5' >/dev/null || fail "Spark Q4 model missing"

# Only after the working model and OpenBot are verified, remove the unusable 8.2GB BF16 copy.
if "$OLLAMA_BIN" list | grep -F "$HEAVY_MODEL" >/dev/null 2>&1; then
  say "Removing unusable 8.2GB BF16 duplicate"
  "$OLLAMA_BIN" rm "$HEAVY_MODEL" || true
fi

echo
echo "SENIOR SPARK CUTOVER = PASS"
echo "Model:   $MODEL (Spark-X2.5-4B Q4_K_M)"
echo "OpenBot: http://localhost:3010"
echo "Senior:  http://localhost:3010/bot"
echo "Backup:  $BACKUP"
