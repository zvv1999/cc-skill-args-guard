#!/usr/bin/env bash
# cc-skill-args-guard — install
# Patches ~/.claude/CLAUDE.md and ~/.claude/settings.json to defend against
# stale skill ARGUMENTS leaking across context compaction.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER_BEGIN="<!-- cc-skill-args-guard BEGIN -->"
MARKER_END="<!-- cc-skill-args-guard END -->"

if [[ ! -d "$CLAUDE_DIR" ]]; then
  echo "✗ $CLAUDE_DIR not found. Install Claude Code first." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "✗ python3 required (used for safe JSON editing)." >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR/hooks"

# 1. Timestamped backups
ts=$(date +%Y%m%d-%H%M%S)
for f in CLAUDE.md settings.json; do
  if [[ -f "$CLAUDE_DIR/$f" ]]; then
    cp "$CLAUDE_DIR/$f" "$CLAUDE_DIR/$f.bak.$ts"
  fi
done
echo "✓ Backups: $CLAUDE_DIR/{CLAUDE.md,settings.json}.bak.$ts"

# 2. Install the hook script
cp "$SCRIPT_DIR/hooks/stale-args-guard.sh" "$CLAUDE_DIR/hooks/stale-args-guard.sh"
chmod +x "$CLAUDE_DIR/hooks/stale-args-guard.sh"
echo "✓ Hook script: $CLAUDE_DIR/hooks/stale-args-guard.sh"

# 3. Patch settings.json (idempotent)
HOOK_CMD="bash \"$CLAUDE_DIR/hooks/stale-args-guard.sh\""
python3 - "$CLAUDE_DIR/settings.json" "$HOOK_CMD" <<'PYEOF'
import json, sys, os
path, hook_cmd = sys.argv[1], sys.argv[2]
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        try: cfg = json.load(f)
        except json.JSONDecodeError as e:
            print(f"✗ {path} is not valid JSON: {e}", file=sys.stderr); sys.exit(1)
hooks = cfg.setdefault("hooks", {})
session_start = hooks.setdefault("SessionStart", [])
# Drop any prior entries referencing our hook script
session_start[:] = [
    entry for entry in session_start
    if not any("stale-args-guard.sh" in (h.get("command") or "") for h in (entry.get("hooks") or []))
]
session_start.append({
    "hooks": [{"type": "command", "command": hook_cmd}]
})
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"✓ settings.json: SessionStart hook registered")
PYEOF

# 4. Patch CLAUDE.md (idempotent via markers)
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
touch "$CLAUDE_MD"
python3 - "$CLAUDE_MD" "$SCRIPT_DIR/fragments/claude-md.md" "$MARKER_BEGIN" "$MARKER_END" <<'PYEOF'
import sys
target, fragment_path, begin, end = sys.argv[1:5]
with open(target) as f: content = f.read()
with open(fragment_path) as f: fragment = f.read()
# Strip any prior block
if begin in content:
    pre = content.split(begin)[0]
    post = content.split(end)[1]
    content = pre.rstrip() + "\n\n"
new = f"{content}{begin}\n{fragment.strip()}\n{end}\n"
with open(target, "w") as f: f.write(new)
print(f"✓ CLAUDE.md: guard rule appended (between markers)")
PYEOF

cat <<EOF

✅ cc-skill-args-guard installed.

What was patched:
  • $CLAUDE_DIR/hooks/stale-args-guard.sh       (new)
  • $CLAUDE_DIR/settings.json                    (SessionStart hook added)
  • $CLAUDE_DIR/CLAUDE.md                        (guard rule appended)

Start a new Claude Code session for the hook to fire.
EOF
