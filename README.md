# cc-skill-args-guard

> A guard rail for Claude Code: stops stale skill `ARGUMENTS` from prior sessions being treated as the current request after context compaction.

## The bug

When you invoke a Claude Code skill with arguments (e.g. `/frontend-design:frontend-design redo the top marquee`), the CLI stores those arguments as `lastInvocationArgs` for that skill. On **every subsequent request**, the system prompt includes:

```
### Skill: frontend-design:frontend-design
[full skill body]

ARGUMENTS: redo the top marquee
```

The arguments have **no timestamp and no expiration**. They are preserved across context compaction and across sessions — even days later, long after the user has moved on to a different topic.

After compaction, the conversation history that originally contextualized the invocation is gone, so the model sees the stale arguments and mistakes them for a fresh request. Result: the model silently resumes work on an abandoned topic, ignoring the user's current message.

### Symptoms

- After `/compact` or a resumed session, the model starts working on a topic you discussed days ago.
- The model references a skill's `ARGUMENTS` as if you'd just typed it.
- Your actual latest request is treated as secondary or ignored.

### Verification

Inspect your transcript at `~/.claude/projects/<project>/<session>.jsonl`:

- The offending `ARGUMENTS:` text only appears as a `user` message on the **original invocation day**.
- It does **not** appear in any `user`/`system` message after that — confirming it lives in the system prompt, which the transcript doesn't store.
- It does appear in assistant responses as the model cites "what the user asked", which is the behavioral fingerprint of the leak.

## The fix (three layers)

This package installs three independent defenses. Any single one prevents the bug; all three together provide defense in depth.

### Layer 1 — `SessionStart` hook (settings.json)

CLI executes a shell script on every session start and injects its stdout as system context. Tells the model: *"ARGUMENTS may be stale; cross-check against the resume summary."* The CLI forces this into context — the model can't opt out.

### Layer 2 — `CLAUDE.md` rule

A mandatory rule appended to `~/.claude/CLAUDE.md`. CLAUDE.md loads with every system prompt and **overrides skill context**. The rule says: when resuming after compaction, the summary's `All user messages` list is authoritative; if skill ARGUMENTS conflict, follow the summary.

### Layer 3 — project memory (optional, manual)

Per-project memory files documenting the current main task and "no style detours" feedback. Helps the model stay on-topic. Not installed by `install.sh` — write these yourself per project as needed.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zvv1999/cc-skill-args-guard/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/zvv1999/cc-skill-args-guard
cd cc-skill-args-guard
./install.sh
```

`install.sh` is idempotent and creates timestamped backups of `~/.claude/CLAUDE.md` and `~/.claude/settings.json` before patching.

## Uninstall

```bash
./uninstall.sh
```

Restores from the most recent backup.

## What this does NOT fix

The root cause lives in the Claude Code binary's system-prompt construction logic. This package only patches **model behavior** — it makes the model immune to the stale arguments by forcing cross-verification. The actual `lastInvocationArgs` leak still happens upstream.

Track the upstream fix: https://github.com/anthropics/claude-code/issues/69679.

## Requirements

- macOS or Linux (uses `bash`, `python3`, `cp`, `date`)
- Claude Code ≥ 2.1 (hooks + SessionStart support)
- Existing `~/.claude/CLAUDE.md` and `~/.claude/settings.json` (created automatically if missing)

## License

MIT
