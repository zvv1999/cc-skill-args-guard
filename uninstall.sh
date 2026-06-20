#!/usr/bin/env bash
# cc-skill-args-guard — uninstall
# Restores ~/.claude/CLAUDE.md and ~/.claude/settings.json from the most recent backup.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
MARKER_BEGIN="<!-- cc-skill-args-guard BEGIN -->"
MARKER_END="<!-- cc-skill-args-guard END -->"

if ! command -v python3 >/dev/null 2>&1; then
  echo "✗ python3 required." >&2
  exit 1
fi

# 1. Remove hook script
if [[ -f "$CLAUDE_DIR/hooks/stale-args-guard.sh" ]]; then
  rm "$CLAUDE_DIR/hooks/stale-args-guard.sh"
  echo "✓ Removed hook script"
fi

# 2. Strip hook from settings.json
if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
  python3 - "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, sys, os
path = sys.argv[1]
with open(path) as f: cfg = json.load(f)
hooks = cfg.get("hooks", {})
for event in list(hooks.keys()):
    entries = hooks[event]
    kept = [
        entry for entry in entries
        if not any("stale-args-guard.sh" in (h.get("command") or "") for h in (entry.get("hooks") or []))
    ]
    if kept: hooks[event] = kept
    else: del hooks[event]
if not hooks: cfg.pop("hooks", None)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("✓ settings.json: hook removed")
PYEOF
fi

# 3. Strip guard rule from CLAUDE.md
if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
  python3 - "$CLAUDE_DIR/CLAUDE.md" "$MARKER_BEGIN" "$MARKER_END" <<'PYEOF'
import sys
target, begin, end = sys.argv[1:4]
with open(target) as f: content = f.read()
if begin in content and end in content:
    pre = content.split(begin)[0]
    post = content.split(end)[1]
    content = pre.rstrip() + "\n" + post.lstrip()
    with open(target, "w") as f: f.write(content)
    print("✓ CLAUDE.md: guard rule removed")
else:
    print("ℹ CLAUDE.md: no guard block found (already clean)")
PYEOF
fi

# 4. List available backups in case user wants to fully restore
echo ""
echo "Backups still on disk (manual restore if needed):"
ls -1 "$CLAUDE_DIR"/*.bak.* 2>/dev/null || echo "  (none)"
