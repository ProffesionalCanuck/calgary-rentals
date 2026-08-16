#!/usr/bin/env bash
# Cut Ollama's outbound network access. Inference is unaffected -- it is
# entirely local once weights are on disk. Only pulls/update-checks break,
# which is the point.
#
# Ollama has no built-in "offline" flag, so this is enforced at the
# environment / firewall layer. Three methods; pick one with METHOD=.
set -euo pipefail

METHOD="${METHOD:-env}"   # env | firewall | verify

# Loopback-only bind. This is already Ollama's default; set it explicitly so
# nothing later exposes the daemon to the LAN.
BIND_ADDR="${BIND_ADDR:-127.0.0.1:11434}"

lockdown_env() {
  echo "==> Writing systemd drop-in for the ollama service"
  echo "    (black-hole proxy => outbound HTTP fails fast, inference untouched)"

  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/offline.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=${BIND_ADDR}"
Environment="HTTP_PROXY=http://127.0.0.1:1"
Environment="HTTPS_PROXY=http://127.0.0.1:1"
Environment="NO_PROXY="
EOF

  sudo systemctl daemon-reload
  sudo systemctl restart ollama
  echo "==> Done. Verify with: METHOD=verify ./lockdown.sh"
}

lockdown_firewall() {
  echo "==> Adding iptables OUTPUT rules scoped to the 'ollama' service user"

  if ! id ollama >/dev/null 2>&1; then
    echo "No 'ollama' system user -- you likely run it as yourself." >&2
    echo "Use METHOD=env instead, or run Ollama in Docker (see README)." >&2
    exit 1
  fi

  # Loopback stays open so your own clients can reach :11434.
  sudo iptables -C OUTPUT -m owner --uid-owner ollama -o lo -j ACCEPT 2>/dev/null \
    || sudo iptables -A OUTPUT -m owner --uid-owner ollama -o lo -j ACCEPT
  sudo iptables -C OUTPUT -m owner --uid-owner ollama -j REJECT 2>/dev/null \
    || sudo iptables -A OUTPUT -m owner --uid-owner ollama -j REJECT

  echo "==> Rules active. These do NOT survive reboot unless you persist them:"
  echo "    Debian/Ubuntu: sudo apt install iptables-persistent && sudo netfilter-persistent save"
  echo "    RHEL/Fedora:   sudo service iptables save"
}

verify() {
  echo "==> Daemon reachable?"
  curl -sf "http://${BIND_ADDR}/api/tags" >/dev/null \
    && echo "    OK -- local API responds" \
    || { echo "    FAIL -- daemon not answering on ${BIND_ADDR}"; exit 1; }

  echo "==> Local inference still works?"
  local first_model
  first_model="$(ollama list | awk 'NR==2 {print $1}')"
  if [ -z "$first_model" ]; then
    echo "    SKIP -- no models on disk. Run ./setup.sh first."
  else
    ollama run "$first_model" "reply with the single word: ok" >/dev/null 2>&1 \
      && echo "    OK -- $first_model generated locally" \
      || echo "    FAIL -- inference broken, lockdown was too aggressive"
  fi

  echo "==> Outbound pull correctly BLOCKED?"
  if ollama pull tinyllama >/dev/null 2>&1; then
    echo "    FAIL -- pull succeeded, egress is still open"
    exit 1
  else
    echo "    OK -- pull refused, egress is closed"
  fi

  echo
  echo "Offline lockdown verified."
}

case "$METHOD" in
  env)      lockdown_env ;;
  firewall) lockdown_firewall ;;
  verify)   verify ;;
  *) echo "Unknown METHOD='$METHOD' (want: env | firewall | verify)" >&2; exit 1 ;;
esac
