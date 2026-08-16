# Offline Ollama + DeepSeek Harness

A fully local agent stack: model weights on disk, egress closed, and an agent
harness driving it. Nothing leaves the machine after setup.

## Order of operations

```bash
./setup.sh                  # 1. pull models  (NEEDS NETWORK)
./lockdown.sh               # 2. close egress
METHOD=verify ./lockdown.sh # 3. prove it worked
./dsh-local.sh              # 4. run the agent against local Ollama
```

Step 1 is the only one that touches the internet. Do not skip ahead — after
lockdown, pulling is supposed to fail.

## What each piece does

| File | Purpose |
|---|---|
| `setup.sh` | Pulls the model list to local disk. Idempotent. |
| `lockdown.sh` | Cuts Ollama's outbound access. `METHOD=env` (systemd drop-in, default), `METHOD=firewall` (iptables, scoped to the ollama user), `METHOD=verify` (test the whole thing). |
| `dsh-local.sh` | Launches DeepSeek Harness pointed at `localhost:11434/v1` instead of DeepSeek's API. |
| `uncensored.Modelfile` | A local variant with no assistant persona and compliance-tuned sampling. |

## Why this works at all

Ollama only uses the network to **download** models and check for updates.
Inference is 100% local the moment the weights are on disk. So "offline" is
not a feature you enable — it's the natural state, and the scripts here just
enforce it so nothing re-opens the connection behind your back.

The `env` method sets a black-hole proxy (`http://127.0.0.1:1`), so outbound
HTTP fails instantly while local inference is untouched. The `firewall` method
is the harder guarantee: an iptables `REJECT` on the `ollama` user's egress,
with loopback kept open so your own clients still reach `:11434`.

## Fully air-gapped machine

No network at all on the target? Pull on a connected box, then copy the model
directory across. That directory is the entire state:

```
~/.ollama/models                    # user install
/usr/share/ollama/.ollama/models    # systemd service install
```

Copy both `blobs/` and `manifests/`. No registry call is needed afterward.

## Docker alternative

Cleanest isolation — no firewall rules, no systemd editing:

```bash
docker run -d --name ollama -v ollama:/root/.ollama \
  -p 127.0.0.1:11434:11434 ollama/ollama
docker exec ollama ollama pull deepseek-r1:7b   # pull once
docker network disconnect bridge ollama          # now airgapped
```

## Uncensored models

Two different things get called "uncensored", and only one of them works:

**Prompt/sampling changes** (`uncensored.Modelfile`) — adjusts the system
prompt and sampling. Removes hedging, disclaimers, and the assistant persona.
Does **not** remove trained-in refusals, because it never touches the weights.

**Models without the refusal training** — this is the real lever. Pull a base
model that was fine-tuned to drop refusal behavior:

```bash
ollama pull dolphin-mistral:7b       # Dolphin series, refusals trained out
ollama pull dolphin-mixtral:8x7b     # bigger, needs ~26GB
ollama pull huihui_ai/deepseek-r1-abliterated:7b   # abliterated R1
```

*Abliteration* identifies the internal direction that encodes refusal and
projects it out of the weights. The model keeps its capabilities and loses the
ability to refuse. Search the Ollama registry for `abliterated`, `uncensored`,
or `dolphin` tags — there are abliterated variants of most popular bases.

Then layer the Modelfile on top for tone:

```bash
ollama create my-local -f uncensored.Modelfile
ollama run my-local
```

Practical caveats: refusal training and instruction-following share machinery,
so heavily abliterated models are often noticeably worse at following complex
instructions and more prone to confidently stating false things. The removed
behavior includes "I don't know" as well as "I won't." Keep a stock model
around to cross-check factual answers.

## DeepSeek Harness notes

`dsh` is **v0.1 developer preview** (MIT). DeepSeek explicitly warn about
breaking changes — don't build anything load-bearing on it yet.

Its architecture is plugin-first ("everything is a plugin"): models, tools,
skills, sessions, sandboxes, filesystems, the agent loop, and the UI are all
swappable. That's exactly why the local swap works — the model is just another
plugin, so you repoint it at an OpenAI-compatible URL and it talks to Ollama.

If `dsh-local.sh` doesn't take the environment variables, the model plugin
wants file config instead; see the CONFIG DISCOVERY comment at the bottom of
that script.

## Sizing

Roughly 1GB of RAM/VRAM per billion params at Q4 quantization:

| Model | Approx. footprint |
|---|---|
| 3B | ~2 GB |
| 7B | ~5 GB |
| 8x7B (mixtral) | ~26 GB |
| 70B | ~40 GB+ |

DeepSeek V4-Pro is ~1.6T params — not a local model on consumer hardware.
R1 remains the practical local pick for reasoning work.
