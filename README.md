# oclaude

opencode, then claude.

A tiny wrapper that lets you run [Claude Code](https://github.com/anthropics/claude-code) against
any of the coding plans you've already configured in [opencode](https://opencode.ai) — Z.ai (GLM),
MiniMax, or Alibaba (Qwen) — instead of your Anthropic account, without hand-editing environment
variables every time.

It reuses opencode's own stored API keys (`~/.local/share/opencode/auth.json`), so there's nothing
to configure and no secrets live in this script.

## Requirements

- [opencode](https://opencode.ai) installed and logged in to at least one of the plans below
  (`opencode auth login`)
- [Claude Code](https://claude.com/claude-code) installed (`claude` on your `PATH`)
- `bash` and `python3` (used only to read opencode's local auth file)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/venkycs/oclaude/main/bin/oclaude -o ~/.local/bin/oclaude
chmod +x ~/.local/bin/oclaude
```

Make sure `~/.local/bin` is on your `PATH`.

## Usage

```sh
oclaude
```

You'll get a menu:

```
Select a plan for Claude Code:
  1) Z.AI Coding Plan (GLM)
  2) MiniMax Token Plan
  3) Alibaba Token Plan (Qwen)
  4) Anthropic default (your normal Claude account/API key)
>
```

Pick one, and it `exec`s straight into `claude` with the right `ANTHROPIC_BASE_URL`,
`ANTHROPIC_AUTH_TOKEN`, and model-tier env vars set for that plan — only for that process, your
shell's own environment is untouched. Any extra args are passed straight through to `claude`:

```sh
oclaude -p "fix the failing test"
```

## What it sets, per plan

| Plan | Base URL | Models |
|---|---|---|
| Z.ai (GLM) | `api.z.ai/api/anthropic` | Haiku → `glm-4.7`, Sonnet/Opus → `glm-5.2` |
| MiniMax | `api.minimax.io/anthropic` | all tiers → `MiniMax-M3` |
| Alibaba (Qwen) | `token-plan.ap-southeast-1.maas.aliyuncs.com/apps/anthropic` | Haiku → `qwen3.6-flash`, Sonnet/Opus → `qwen3.8-max`, subagent → `qwen3.7-max` |
| Anthropic default | — | unsets all overrides |

## License

MIT
