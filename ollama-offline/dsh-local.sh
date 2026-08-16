#!/usr/bin/env bash
# Launch DeepSeek Harness (dsh) against the LOCAL Ollama daemon instead of
# DeepSeek's hosted API, so the whole agent loop stays on this machine.
#
# dsh is v0.1 developer preview -- DeepSeek warn to expect breaking changes.
# The provider-config key names below are the conventional OpenAI-compatible
# ones; if dsh ignores them, see CONFIG DISCOVERY at the bottom of this file.
set -euo pipefail

OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://127.0.0.1:11434/v1}"
MODEL="${MODEL:-deepseek-r1:7b}"

# --- preflight ------------------------------------------------------------
echo "==> Checking local Ollama at ${OLLAMA_ENDPOINT}"
if ! curl -sf "${OLLAMA_ENDPOINT%/v1}/api/tags" >/dev/null; then
  echo "Ollama is not answering. Start it with: ollama serve" >&2
  exit 1
fi

if ! ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
  echo "Model '$MODEL' is not on disk. Run ./setup.sh first (needs network)." >&2
  exit 1
fi
echo "    OK -- $MODEL available locally"

# --- point dsh at Ollama --------------------------------------------------
# Ollama serves an OpenAI-compatible API at /v1 and ignores the key entirely,
# but most clients refuse to start without one, so send a dummy.
export OPENAI_BASE_URL="$OLLAMA_ENDPOINT"
export OPENAI_API_KEY="ollama-local-no-key-needed"
export DEEPSEEK_BASE_URL="$OLLAMA_ENDPOINT"
export DEEPSEEK_API_KEY="ollama-local-no-key-needed"

echo "==> Launching dsh web UI against local Ollama (model: $MODEL)"
exec npx @deepseek-ai/dsh web

# --- CONFIG DISCOVERY -----------------------------------------------------
# If dsh still tries to reach api.deepseek.com, its model plugin wants config
# in a file rather than the environment. To find the real schema:
#
#   git clone https://github.com/deepseek-ai/deepseek-harness.git
#   cd deepseek-harness && cat docs/architecture.md docs/user/guide/index.md
#   grep -rn "baseURL\|base_url\|apiKey" src/ | head -40
#
# Everything in dsh is a plugin, including the model, so the fix is always
# "configure or swap the model plugin" -- point it at an OpenAI-compatible
# base URL and it will speak to Ollama.
#
# Sanity check that the lockdown is holding while dsh runs:
#   METHOD=verify ./lockdown.sh
