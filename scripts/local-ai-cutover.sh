#!/usr/bin/env bash
set -Eeuo pipefail

MODEL="qwen3:4b-instruct-2507-q4_K_M"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

say(){ printf '\n== %s ==\n' "$*"; }
fail(){ printf '\nCUTOVER FAILED: %s\n' "$*" >&2; exit 1; }

say "Senior local AI cutover"

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v docker >/dev/null 2>&1 || fail "Docker is required"
OLLAMA_BIN="$(command -v ollama || true)"
[[ -n "$OLLAMA_BIN" ]] || fail "Ollama is not on PATH. Close Git Bash, reopen it, and run this script again."
echo "Ollama: $OLLAMA_BIN"

# Start the native Windows Ollama server if the installer did not start it.
if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  say "Starting Ollama"
  OLLAMA_HOST=127.0.0.1:11434 nohup "$OLLAMA_BIN" serve > "$HOME/ollama-serve.log" 2>&1 &
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

say "Installing $MODEL"
"$OLLAMA_BIN" pull "$MODEL"

say "Testing local model"
TEST_JSON="$(curl -fsS --max-time 180 http://127.0.0.1:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: SENIOR LOCAL AI READY\"}],\"stream\":false}")" || fail "Local model API test failed"
printf '%s\n' "$TEST_JSON" | grep -q 'SENIOR LOCAL AI READY' || fail "Model responded, but acceptance phrase was missing"
echo "Local model: PASS"

[[ -f .env ]] || fail ".env not found in $ROOT"
BACKUP=".env.pre-ollama.$(date +%Y%m%d-%H%M%S).bak"
cp .env "$BACKUP"
echo "Configuration backup created locally: $BACKUP"

setenv(){
  local key="$1" value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '\n%s=%s\n' "$key" "$value" >> .env
  fi
}

say "Switching OpenBot from paid OpenAI inference to local Ollama"
setenv OPENAI_BASE_URL "http://127.0.0.1:11434/v1"
# Keep a non-secret placeholder because OpenAI-compatible clients commonly require a non-empty key.
setenv OPENAI_API_KEY "ollama-local"
setenv BOT_PROVIDER "openai"
setenv BOT_MODEL "$MODEL"
setenv AGENT_BOT_MODEL "$MODEL"
# Docker Desktop route for any containerized Bot that later needs the same endpoint.
setenv OPENAI_CONTAINER_BASE_URL "http://host.docker.internal:11434/v1"

if command -v git >/dev/null 2>&1; then
  git status --short
fi

say "Restarting OpenBot"
# Restart so the API server definitely reloads OPENAI_BASE_URL and the local model.
# --keep-computers preserves browser sessions; stop.sh deletes no data or volumes.
bash scripts/stop.sh --keep-computers
bash scripts/start.sh

say "Verifying configuration"
grep -E '^(OPENAI_BASE_URL|OPENAI_CONTAINER_BASE_URL|OPENAI_API_KEY|BOT_PROVIDER|BOT_MODEL|AGENT_BOT_MODEL)=' .env | sed 's/^OPENAI_API_KEY=.*/OPENAI_API_KEY=[LOCAL PLACEHOLDER]/'
"$OLLAMA_BIN" ps || true

echo
echo "LOCAL AI CUTOVER = PASS"
echo "OpenBot: http://localhost:3010"
echo "Senior:  http://localhost:3010/bot"
echo "Rollback backup (only if needed): $BACKUP"
