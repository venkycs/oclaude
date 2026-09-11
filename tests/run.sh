#!/usr/bin/env bash
# oclaude test suite — self-contained, no real API calls, no network needed.
#
# Uses a stub `claude`, a fake $HOME, and a seeded model-catalog cache, so the
# OpenRouter "intelligence" (alias resolution, unknown-model rejection, catalog
# listing) is tested deterministically offline.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCLAUE="$REPO/bin/oclaude"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        got: %s\n' "$2"; }

expect_ok() { # $1 name, $2.. cmd
  local name="$1"; shift
  local out; out="$("$@" 2>&1)" && ok "$name" || bad "$name" "$out"
  LAST_OUT="$out"
}
expect_fail() { # $1 name, $2.. cmd (must exit non-zero)
  local name="$1"; shift
  local out; out="$("$@" 2>&1)" && bad "$name (unexpectedly succeeded)" "$out" || ok "$name"
  LAST_OUT="$out"
}
expect_in() { # $1 name, $2 needle (checked against LAST_OUT)
  if grep -q "$2" <<<"$LAST_OUT"; then ok "$1"; else bad "$1" "missing '$2' in: $LAST_OUT"; fi
}

# --- fixtures ----------------------------------------------------------------

# stub claude prints the env it was handed
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "BASE=$ANTHROPIC_BASE_URL TOK=${ANTHROPIC_AUTH_TOKEN:0:8} MODEL=${ANTHROPIC_MODEL:--} HAIKU=${ANTHROPIC_DEFAULT_HAIKU_MODEL:--} SONNET=${ANTHROPIC_DEFAULT_SONNET_MODEL:--} SUB=${CLAUDE_CODE_SUBAGENT_MODEL:--} DISC=${CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY:--} ARGS=[$*]"
EOF
chmod +x "$TMP/bin/claude"

# home with keys for every provider + a fresh (never-stale) catalog cache
mkdir -p "$TMP/home/.local/share/opencode" "$TMP/home/.cache/oclaude"
cat > "$TMP/home/.local/share/opencode/auth.json" <<'EOF'
{"zai-coding-plan":{"type":"api","key":"sk-zai-1"},
 "zai-teams-plan":{"type":"api","key":"sk-zait-1"},
 "minimax-coding-plan":{"type":"api","key":"sk-mm-1"},
 "alibaba-token-plan":{"type":"api","key":"sk-ali-1"},
 "openrouter":{"type":"api","key":"sk-or-1"}}
EOF
cat > "$TMP/home/.cache/oclaude/openrouter-models.json" <<'EOF'
{"data":[
 {"id":"z-ai/glm-4.7","created":1000},
 {"id":"z-ai/glm-5.2","created":1000},
 {"id":"minimax/minimax-m3","created":1000},
 {"id":"qwen/qwen3.6-flash","created":1000},
 {"id":"qwen/qwen3.7-max","created":1000},
 {"id":"qwen/qwen3.8-max-0112","created":1000},
 {"id":"qwen/qwen3.8-max-0902","created":2000},
 {"id":"qwen/qwen3.8-max-0902:batch","created":3000},
 {"id":"deepseek/deepseek-v4","created":1000}
]}
EOF

# empty home: no auth file at all
mkdir -p "$TMP/empty"

STUB_PATH="$TMP/bin:$PATH"
o()    { HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" "$@"; }
o_in() { HOME="$TMP/empty" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" "$@"; }

echo "== syntax =="
bash -n "$OCLAUE" && ok "bin/oclaude" || bad "bin/oclaude"
bash -n "$REPO/install.sh" && ok "install.sh" || bad "install.sh"

echo "== commands =="
expect_ok  "version" o version
expect_in  "version output" "oclaude "
expect_ok  "help" o help
expect_in  "help mentions setup" "setup"

echo "== plan launches (env seen by claude) =="
expect_ok "1 zai coding" o 1
expect_in  "  zai base+models" "BASE=https://api.z.ai/api/anthropic .*HAIKU=glm-5.3-flash SONNET=glm-5.3"
expect_ok "2 zai teams" o 2
expect_in  "  teams same endpoint+models, own key" "BASE=https://api.z.ai/api/anthropic TOK=sk-zait- .*HAIKU=glm-5.3-flash SONNET=glm-5.3"
expect_ok "3 minimax" o 3
expect_in  "  minimax model" "MODEL=MiniMax-M3"
expect_ok "4 alibaba" o 4
expect_in  "  alibaba tiers" "MODEL=qwen3.8-max HAIKU=qwen3.6-flash .*SUB=qwen3.7-max"
expect_ok "5 anthropic unsets everything" o 5
expect_in  "  clean env" "BASE= TOK= MODEL=- .*DISC=-"
expect_ok "6 openrouter-glm" o 6
expect_in  "  glm slugs + discovery" "BASE=https://openrouter.ai/api .*HAIKU=z-ai/glm-4.7 SONNET=z-ai/glm-5.2 .*DISC=1"
expect_ok "7 openrouter-minimax" o 7
expect_in  "  minimax slug" "MODEL=minimax/minimax-m3 .*DISC=1"
expect_ok "8 openrouter-qwen resolves alias to newest snapshot" o 8
expect_in  "  qwen3.8-max -> -0902 (not 0112, not :batch)" "MODEL=qwen/qwen3.8-max-0902 HAIKU=qwen/qwen3.6-flash .*SUB=qwen/qwen3.7-max"
expect_ok "9 custom model" env OPENROUTER_MODEL=deepseek/deepseek-v4 HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" 9
expect_in  "  custom all tiers" "MODEL=deepseek/deepseek-v4 HAIKU=deepseek/deepseek-v4 SONNET=deepseek/deepseek-v4"

echo "== model intelligence =="
expect_ok "alias resolution for custom model" env OPENROUTER_MODEL=qwen/qwen3.8-max HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" 9
expect_in  "  resolved to -0902" "MODEL=qwen/qwen3.8-max-0902"
expect_fail "unknown model rejected when catalog known" env OPENROUTER_MODEL=acme/nope-1 HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" 9
LAST_OUT="$(env OPENROUTER_MODEL=acme/nope-1 HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" 9 2>&1 || true)"
expect_in  "  error suggests browsing" "oclaude models"
expect_fail "9 without OPENROUTER_MODEL errors" env HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" 9
expect_ok "models list from cache" o models qwen3.8
expect_in  "  lists both snapshots" "qwen/qwen3.8-max-0112"
expect_ok "models filter miss is fine" o models zzzz
expect_in  "  says no match" "no models match"

echo "== selection =="
expect_ok "prefix id" o openrouter-q
expect_ok "full id with passthrough args" o openrouter-glm -p "hello world"
expect_in  "  args passed" "ARGS=\[-p hello world\]"
expect_fail "ambiguous prefix" o openrouter
expect_fail "unknown word" o notaplan
expect_fail "menu: out of range" o_in 99
expect_ok "anthropic works without auth file" o_in anthropic
expect_fail "keyed plan without auth file, non-tty: clean error" o_in 1
LAST_OUT="$(o_in 1 2>&1 || true)"
expect_in  "  points to setup" "oclaude setup"

echo "== menu =="
LAST_OUT="$(echo 1 | HOME="$TMP/home" PATH="$STUB_PATH" OCLAUDE_OFFLINE=1 "$OCLAUE" 2>/dev/null)"
expect_in "menu shows all 9 options" "9) OpenRouter: any model"
expect_in "menu marks configured plans" "6) OpenRouter: Z.AI GLM ✓"
expect_in "menu marks teams plan configured" "2) Z.AI Coding Teams (GLM) ✓"
expect_fail "ambiguous zai prefix now errors" o zai
LAST_OUT="$(o zai 2>&1 || true)"
expect_in  "  ambiguity message" "matches more than one plan"

echo "== setup =="
SETUP_HOME="$TMP/setup"; mkdir -p "$SETUP_HOME"
s() { HOME="$SETUP_HOME" PATH="$STUB_PATH" OCLAUDE_SKIP_VERIFY=1 OCLAUDE_OFFLINE=1 "$OCLAUE" setup; }
printf '1\nsk-or-v1-aaaaaaaaaaaaaaaaaaaa\n2\nsk-zai-zzzzzzzzzzzzzz\n3\nsk-zait-tttttttttttttt\n\n' | s > /dev/null
if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["openrouter"]["key"].startswith("sk-or-v1-aaaa")
assert d["zai-coding-plan"]["key"].startswith("sk-zai-")
assert d["zai-teams-plan"]["key"].startswith("sk-zait-")
' "$SETUP_HOME/.local/share/opencode/auth.json" 2>/dev/null; then
  ok "setup creates auth.json with all keys"
else
  bad "setup creates auth.json with all keys"
fi
LAST_OUT="$(printf '2\nx\n\n' | s 2>&1)"
expect_in "setup masks stored keys" "sk-or-v1…aaaa"
expect_in "setup removes on x" "Removed"
if grep -q '"zai-coding-plan"' "$SETUP_HOME/.local/share/opencode/auth.json"; then bad "key actually removed"; else ok "key actually removed"; fi
if grep -q '"zai-teams-plan"' "$SETUP_HOME/.local/share/opencode/auth.json"; then ok "teams key untouched by coding-plan removal"; else bad "teams key untouched by coding-plan removal"; fi
authjson="$SETUP_HOME/.local/share/opencode/auth.json"
# GNU stat -c works on Linux and fails on macOS (BSD stat needs -f '%Lp')
perms="$(stat -c '%a' "$authjson" 2>/dev/null || stat -f '%Lp' "$authjson" 2>/dev/null)"
[[ "$perms" == "600" ]] && ok "auth.json is 0600" || bad "auth.json is 0600" "mode=$perms"

echo "== update & installer (file:// sources, never the network) =="
mkdir -p "$TMP/upd" && cp "$OCLAUE" "$TMP/upd/oclaude" && chmod +x "$TMP/upd/oclaude"
expect_ok "self-update" env HOME="$TMP/home" PATH="$TMP/upd:$STUB_PATH" OCLAUDE_OFFLINE=1 OCLAUDE_REPO="file://$REPO" "$TMP/upd/oclaude" update
expect_in  "  reports new version" "Updated"
INST="$TMP/instdir"
expect_ok "installer, non-tty" env HOME="$TMP/insthome" OCLAUDE_INSTALL_DIR="$INST" OCLAUDE_SRC="file://$REPO" bash "$REPO/install.sh"
[[ -x "$INST/oclaude" ]] && ok "installer produced executable" || bad "installer produced executable"
expect_in  "installer stderr stays clean (no /dev/tty noise)" "^==> Installing"

echo
echo "passed: $PASS  failed: $FAIL"
(( FAIL == 0 ))
