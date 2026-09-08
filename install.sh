#!/usr/bin/env bash
# oclaude one-touch installer:
#   curl -fsSL https://raw.githubusercontent.com/venkycs/oclaude/main/install.sh | bash
#
# Installs oclaude to ~/.local/bin (override: OCLAUDE_INSTALL_DIR), checks
# dependencies, optionally installs Claude Code if missing, optionally runs
# `oclaude setup` to store your API keys. Prompts read from /dev/tty so the
# curl-pipe form works; with no tty it installs non-interactively.
set -euo pipefail

DEST_DIR="${OCLAUDE_INSTALL_DIR:-$HOME/.local/bin}"
SRC="${OCLAUDE_SRC:-https://raw.githubusercontent.com/venkycs/oclaude/main}"
DEST="$DEST_DIR/oclaude"

say() { printf '%s\n' "$*"; }

# Grab the terminal (fd 3) if there is one; `curl | bash` consumes stdin,
# and -r /dev/tty can be true even when no controlling terminal exists.
{ exec 3</dev/tty; } 2>/dev/null || exec 3</dev/null
if [[ -t 3 ]]; then HAVE_TTY=1; else HAVE_TTY=0; fi

# Ask a yes/no question; no tty -> default answer ($2: y/n).
ask_yn() { # $1 question, $2 default
  local def="${2:-y}" ans
  if (( ! HAVE_TTY )); then ans="$def"; else
    local prompt="y/n"; [[ "$def" == "y" ]] && prompt="Y/n" || prompt="y/N"
    read -r -u 3 -p "$1 [$prompt] " ans || ans="$def"
  fi
  case "${ans:-$def}" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

say "==> Installing oclaude to $DEST"

if ! command -v curl >/dev/null 2>&1; then
  say "error: curl is required (this installer uses it)" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
if ! curl -fsSL --max-time 30 "$SRC/bin/oclaude" -o "$DEST"; then
  say "error: could not download $SRC/bin/oclaude" >&2
  exit 1
fi
chmod +x "$DEST"
bash -n "$DEST" || { say "error: downloaded script failed syntax check" >&2; exit 1; }
say "    installed: $DEST ($("$DEST" version))"

# PATH check
case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *)
    say ""
    say "==> NOTE: $DEST_DIR is not on your PATH."
    say "    Add this line to your shell profile (~/.zshrc or ~/.bashrc):"
    say "      export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac

# python3 (used for auth.json handling)
if ! command -v python3 >/dev/null 2>&1; then
  say ""
  say "==> WARNING: python3 not found — oclaude needs it to manage API keys."
  say "    Install it (macOS: xcode-select --install) or keys already in"
  say "    ~/.local/share/opencode/auth.json will still work without it."
fi

# Claude Code itself
say ""
if command -v claude >/dev/null 2>&1; then
  say "==> Claude Code: found ($(command -v claude))"
else
  say "==> Claude Code (claude) not found."
  if (( ! HAVE_TTY )); then
    say "    Install it later with: curl -fsSL https://claude.ai/install.sh | bash"
  elif ask_yn "    Install Claude Code now via the official installer?" "y"; then
    curl -fsSL https://claude.ai/install.sh | bash || say "    (installer failed — install manually: https://claude.com/claude-code)"
  fi
fi

# Keys
say ""
if (( ! HAVE_TTY )); then
  say "==> Done. Next: run 'oclaude setup' to add API keys, then 'oclaude'."
else
  if ask_yn "==> Set up API keys now (oclaude setup)?" "y"; then
    PATH="$DEST_DIR:$PATH" "$DEST" setup || true
    say ""
  fi
  say "==> Done. Run 'oclaude' to pick a plan and launch Claude Code."
fi
