#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODEL="maternion/spark-x2.5:4b"

say(){ printf '\n== %s ==\n' "$*"; }
fail(){ printf '\nFAILED: %s\n' "$*" >&2; exit 1; }

say "VERIFY KING LOCAL MODEL"
TAGS="$(curl -fsS --max-time 8 http://127.0.0.1:11434/api/tags)" || fail "Ollama is not reachable"
printf '%s' "$TAGS" | grep -Fq "$MODEL" || fail "KING Spark model is not registered in Ollama"
echo "KING Spark model: READY"

say "VERIFY OPENBOT LOCAL ROUTING"
grep -Fqx 'OPENAI_BASE_URL=http://127.0.0.1:11434/v1' .env || fail "OPENAI_BASE_URL is not local Ollama"
grep -Fqx 'OPENAI_CONTAINER_BASE_URL=http://host.docker.internal:11434/v1' .env || fail "Container Ollama route is not configured"
grep -Fqx "BOT_MODEL=$MODEL" .env || fail "BOT_MODEL is not Spark Q4"
grep -Fqx "AGENT_BOT_MODEL=$MODEL" .env || fail "AGENT_BOT_MODEL is not Spark Q4"
grep -Fq "default_model: $MODEL" examples/senior/model.yaml || fail "Senior model.yaml is not Spark Q4"
echo "OpenBot local routing: PASS"

say "VERIFY OPENBOT SERVER"
INFO="$(curl -fsS --max-time 8 http://127.0.0.1:3001/api/copilotkit/info)" || fail "OpenBot API is not reachable"
bun -e '
const info = JSON.parse(process.argv[1]);
const agents = Object.keys(info.agents ?? {});
const required = ["senior","pure-profit-health","morrow-grain","ads-senior","luna-kk","publishing-growth"];
const missing = required.filter((id) => !agents.includes(id));
if (missing.length) {
  console.error("Missing required Senior Bots: " + missing.join(", "));
  process.exit(2);
}
console.log("Bots: " + agents.join(", "));
console.log("CopilotKit licence status: " + String(info.licenseStatus ?? "unknown"));
' "$INFO" || fail "OpenBot API is missing one or more required Senior Bots"
echo "OpenBot API + Senior roster: PASS"

say "VERIFY OPENBOT APP"
curl -fsS --max-time 8 http://127.0.0.1:3010/ | grep -qi '<title>[^<]*OpenBot' || fail "OpenBot app is not ready on 3010"
echo "OpenBot app: PASS"

say "VERIFY DOCKER TO KING OLLAMA"
docker compose exec -T agent-bot bun -e '
const model = process.argv[1];
const r = await fetch("http://host.docker.internal:11434/api/chat", {
  method: "POST",
  headers: {"content-type":"application/json"},
  body: JSON.stringify({
    model,
    messages:[{role:"user",content:"Reply briefly that the local route works."}],
    stream:false,
    think:false,
    options:{num_ctx:8192,num_predict:96}
  })
});
if (!r.ok) {
  console.error("HTTP " + r.status + ": " + await r.text());
  process.exit(2);
}
const j = await r.json();
const out = String(j?.message?.content ?? "").trim();
if (!j?.done || !out) {
  console.error(JSON.stringify(j));
  process.exit(3);
}
console.log("Container -> KING Spark: " + out);
' "$MODEL" || fail "Docker containers cannot generate through KING Ollama"
echo "Docker -> KING Ollama: PASS"

echo
echo "KING STAGE 2 = PASS"
echo "Senior:  http://localhost:3010/bot"
echo "OpenBot: http://localhost:3010"
