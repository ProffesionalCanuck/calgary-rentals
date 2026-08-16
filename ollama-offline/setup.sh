#!/usr/bin/env bash
# Pull every model we need while the network is still up.
# Run this BEFORE lockdown.sh -- after lockdown, pulls will fail by design.
set -euo pipefail

OLLAMA_BIN="${OLLAMA_BIN:-ollama}"

# Edit this list. Tags must exist in the registry; check with `ollama show <tag>`.
MODELS=(
  "deepseek-r1:7b"        # reasoning / chain-of-thought
  "qwen2.5-coder:7b"      # code
  "llama3.2:3b"           # small + fast, good fallback
  "nomic-embed-text"      # embeddings, for any RAG work
)

if ! command -v "$OLLAMA_BIN" >/dev/null 2>&1; then
  echo "ollama not found on PATH. Install it first: https://ollama.com/download" >&2
  exit 1
fi

echo "==> Ollama version: $("$OLLAMA_BIN" --version 2>&1 | head -1)"

for model in "${MODELS[@]}"; do
  if "$OLLAMA_BIN" list | awk '{print $1}' | grep -qx "$model"; then
    echo "==> $model already present, skipping"
    continue
  fi
  echo "==> Pulling $model"
  "$OLLAMA_BIN" pull "$model"
done

echo
echo "==> Models on disk:"
"$OLLAMA_BIN" list

cat <<'EOF'

Done. Everything above is now on local disk and needs no network to run.

Model files live in:
  ~/.ollama/models                        (user install)
  /usr/share/ollama/.ollama/models        (systemd service install)

To move these to a machine with no network at all, copy that whole
directory -- both blobs/ and manifests/ -- and nothing else is needed.

Next: ./lockdown.sh
EOF
