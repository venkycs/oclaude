# oclaude

opencode, then claude — now with [OpenRouter](https://openrouter.ai).

A tiny wrapper that runs [Claude Code](https://github.com/anthropics/claude-code) against
alternative providers — Z.ai (GLM), MiniMax, Alibaba (Qwen), or anything on OpenRouter — instead
of your Anthropic account, without hand-editing environment variables every time.

It works **standalone or on top of [opencode](https://opencode.ai)**: API keys are stored in
opencode's own format (`~/.local/share/opencode/auth.json`), created for you by `oclaude setup`.
If you already use opencode, your existing keys are picked up as-is; if you don't, oclaude
manages that file itself.

## How it works

oclaude is a single bash script that sits between you and `claude`:

1. **You pick a plan** — from the interactive menu, or upfront: `oclaude 2`, `oclaude zai-t`,
   `oclaude openrouter-qwen -p "..."`.
2. **It loads that plan's API key** from `~/.local/share/opencode/auth.json` (mode `0600`) — or,
   if none is stored and you're in a terminal, asks you to paste one and saves it there. Keys are
   only ever sent to the provider they belong to.
3. **It `exec`s straight into `claude`** with exactly the environment that plan needs:
   `ANTHROPIC_BASE_URL` (the provider's Anthropic-protocol endpoint), `ANTHROPIC_AUTH_TOKEN`
   (the key), and the model-tier vars (`ANTHROPIC_DEFAULT_HAIKU/SONNET/OPUS_MODEL`, …).

Nothing is written to any Claude Code config file, and your shell's environment is untouched —
the overrides exist only inside the launched process. Close it, and everything is back to your
normal Anthropic setup (`oclaude anthropic` / plan 5 also launches `claude` with all overrides
explicitly unset).

Two behaviors worth knowing:

- **The stored key always wins.** If you `export ANTHROPIC_AUTH_TOKEN=...` in your shell and
  then launch a keyed plan, oclaude replaces it with the key stored for that plan. Keys are
  managed in `auth.json` via `oclaude setup`, not in your shell profile. (The one exception:
  `OPENROUTER_API_KEY` beats the stored OpenRouter key.)
- **`ANTHROPIC_API_KEY` is unset on purpose** — these providers authenticate with a Bearer
  `ANTHROPIC_AUTH_TOKEN`, and leaving `ANTHROPIC_API_KEY` set makes Claude Code send the wrong
  header.

## One-touch install

```sh
curl -fsSL https://raw.githubusercontent.com/venkycs/oclaude/main/install.sh | bash
```

The installer puts `oclaude` in `~/.local/bin`, checks your `PATH` and `python3`, offers to
install Claude Code itself if missing, and offers to run `oclaude setup` so you can paste your
API keys right away. (Manual alternative:
`curl -fsSL .../raw/main/bin/oclaude -o ~/.local/bin/oclaude && chmod +x ~/.local/bin/oclaude`.)

## Quick start

```sh
oclaude setup     # paste API keys (validated for OpenRouter, stored opencode-compatible)
oclaude           # pick a plan, launch Claude Code
```

You'll get a menu (`✓` = a key is configured):

```
Select a plan for Claude Code:
  1) Z.AI Coding Plan (GLM)
  2) Z.AI Coding Teams (GLM)
  3) MiniMax Token Plan
  4) Alibaba Token Plan (Qwen)
  5) Anthropic default (your normal Claude account/API key) ✓
  6) OpenRouter: Z.AI GLM ✓
  7) OpenRouter: MiniMax ✓
  8) OpenRouter: Qwen ✓
  9) OpenRouter: any model ($OPENROUTER_MODEL) ✓
>
```

It `exec`s straight into `claude` with the right `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`,
and model-tier env vars for that plan — only for that process; your shell's environment is
untouched. Any extra args pass through to `claude`:

```sh
oclaude -p "fix the failing test"
```

### Skipping the menu

Give the plan as the first argument — menu number, plan id, or any unique prefix:

```sh
oclaude zai-c          # Z.AI Coding Plan (developers); zai-t for the Teams plan
oclaude 8
oclaude openrouter-qwen -p "..."
OPENROUTER_MODEL=z-ai/glm-5.3 oclaude 9   # any model OpenRouter serves
```

If a plan's key is missing and you're in a terminal, oclaude offers to take it right there and
saves it (OpenRouter keys are validated against the API before storing).

## Configuration: API keys

```sh
oclaude setup
```

walks you through every provider, shows a masked form of what's already stored (`sk-or-v1…aaaa`),
and lets you paste a new key or remove the stored one (`x`). Nothing else is configurable —
plans, endpoints, and model mappings are pinned in the script.

Where each key comes from:

| Provider | Get a key at | Notes |
|---|---|---|
| Z.AI Coding Plan | [z.ai → API Keys](https://z.ai/manage-apikey/apikey-list) | your personal (developer) plan; bills its own quota |
| Z.AI Coding Teams | [z.ai → Team Coding Plan → My Plan](https://z.ai/manage-apikey/coding-plan/team/my-plan) | **not interchangeable** with personal keys — team quota only applies when the team key is used |
| MiniMax | MiniMax platform console | token plan |
| Alibaba (Qwen) | Alibaba Cloud Model Studio (token plan) | |
| OpenRouter | [openrouter.ai/keys](https://openrouter.ai/keys) | prepaid credit; serves every model above |

The two Z.ai entries exist precisely because of that table's second row: developer and Teams
plans share one endpoint and the same models, and only the key decides whose quota is billed —
so oclaude keeps two entries (`zai-c`, `zai-t`) with two separately stored keys.

Key resolution, in order, per launch:

1. `OPENROUTER_API_KEY` in your environment (OpenRouter plans only) — wins over the stored key;
2. the key stored in `auth.json` for that plan;
3. pasted on the spot when launched from a terminal (then saved for next time). Without a
   terminal, a missing key is a clean error pointing at `oclaude setup`.

## Intelligent model handling

The OpenRouter options fetch OpenRouter's live model catalog (cached 24 h in
`~/.cache/oclaude/`):

- **Alias resolution** — you (and the built-in plans) say `qwen/qwen3.8-max`, oclaude resolves it
  to the newest dated snapshot (e.g. `qwen/qwen3.8-max-0902`) automatically. Plans never go stale
  when OpenRouter rotates snapshots.
- **Unknown models rejected up front** — `OPENROUTER_MODEL=acme/nope oclaude 9` fails with a
  pointer to `oclaude models` instead of a cryptic first-request error.
- **Gateway model discovery** — OpenRouter plans set `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1`,
  so Claude Code's `/model` picker lists what the gateway actually serves.
- **Browse the catalog**:

  ```sh
  oclaude models          # everything, with context window and $/M pricing
  oclaude models glm      # filtered
  ```

- **Offline-safe** — `OCLAUDE_OFFLINE=1` (or just no network) skips fetching and falls back to
  the pinned model ids below.

## Commands & env

| Command | Does |
|---|---|
| `oclaude` | interactive plan menu |
| `oclaude <plan\|number> [claude args]` | launch directly |
| `oclaude setup` | add/remove API keys (masked display, OpenRouter validation) |
| `oclaude models [filter]` | list OpenRouter models live |
| `oclaude update` | self-update from this repo |
| `oclaude help` / `version` | usage / version |

| Env | Meaning |
|---|---|
| `OPENROUTER_API_KEY` | OpenRouter key; wins over the stored one |
| `OPENROUTER_MODEL` | model for plan 9 (alias or dated slug) |
| `OCLAUDE_OFFLINE=1` | never hit the network; cached/pinned values only |
| `OCLAUDE_MODELS_TTL` | catalog cache seconds (default 86400) |
| `OCLAUDE_SKIP_VERIFY=1` | skip OpenRouter key validation in setup |
| `OCLAUDE_REPO` | self-update source (forks) |

## What it sets, per plan

| Plan | Base URL | Models |
|---|---|---|
| Z.ai Coding Plan (GLM) | `api.z.ai/api/anthropic` | Haiku → `glm-5.3-flash`, Sonnet/Opus → `glm-5.3` |
| Z.ai Coding Teams (GLM) | `api.z.ai/api/anthropic` | same as Coding Plan, but billed to your Team key |
| MiniMax | `api.minimax.io/anthropic` | all tiers → `MiniMax-M3` |
| Alibaba (Qwen) | `token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic` | Haiku → `qwen3.6-flash`, Sonnet/Opus → `qwen3.8-max`, subagent → `qwen3.7-max` |
| Anthropic default | — | unsets all overrides |
| OpenRouter: GLM | `openrouter.ai/api` | Haiku → `z-ai/glm-4.7`, Sonnet/Opus → `z-ai/glm-5.2` |
| OpenRouter: MiniMax | `openrouter.ai/api` | all tiers → `minimax/minimax-m3` |
| OpenRouter: Qwen | `openrouter.ai/api` | Haiku → `qwen/qwen3.6-flash`, Sonnet/Opus → newest `qwen/qwen3.8-max-*`, subagent → `qwen/qwen3.7-max` |
| OpenRouter: any model | `openrouter.ai/api` | every tier → `$OPENROUTER_MODEL` (resolved) |

The OpenRouter plans mirror the direct ones but bill to your OpenRouter credit. OpenRouter speaks
Claude Code's native Anthropic protocol (`https://openrouter.ai/api`, Bearer auth via
`ANTHROPIC_AUTH_TOKEN`), so no proxy is needed; `ANTHROPIC_API_KEY` stays unset so Claude Code
uses the right header.

The two Z.ai entries use the same endpoint and models but keep **separate stored keys** — per
Z.ai's docs a Team Plan key is not interchangeable with other Z.ai keys, and team quota only
applies when the Team key is used. Pick `zai-c` for your developer (individual) coding plan,
`zai-t` for the Team plan.

## Requirements

- `bash`, `python3`, `curl`
- [Claude Code](https://claude.com/claude-code) (`claude` on your `PATH`) — the installer can set
  this up for you
- An account/key for whichever plans you want (OpenRouter, Z.ai, MiniMax, or Alibaba); keys for
  plans you don't pick are never needed

## Developing

```sh
git clone https://github.com/venkycs/oclaude && cd oclaude
./tests/run.sh        # full suite: stubbed claude, fake $HOME, no network, <5s
bin/oclaude help
```

The suite covers every plan's env vars, alias resolution (newest-snapshot wins, `:batch`
variants excluded), unknown-model rejection, setup (add/mask/remove, `0600` perms), selection
forms, self-update, and the installer — all offline, using a seeded catalog cache and `file://`
sources. CI runs it on Ubuntu and macOS (`.github/workflows/ci.yml`).

To try your checkout without installing it system-wide:

```sh
# install your working copy instead of the released one
OCLAUDE_SRC="file://$PWD" bash install.sh

# or point an installed oclaude's self-update at your checkout
OCLAUDE_REPO="file://$PWD" oclaude update
```

Handy while iterating: `OCLAUDE_OFFLINE=1` (skip catalog fetches), `OCLAUDE_SKIP_VERIFY=1`
(skip key validation), `OCLAUDE_INSTALL_DIR`, `OCLAUDE_MODELS_TTL`. Keep `bin/oclaude` a single
portable bash file — no build step, that's the point.

## License

MIT
