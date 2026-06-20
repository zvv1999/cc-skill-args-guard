#!/usr/bin/env bash
# cc-skill-args-guard — SessionStart hook
# Claude Code executes this on every session start and injects stdout as
# system context. Forces the model to treat stale skill ARGUMENTS with
# suspicion and cross-check against the resume summary.
#
# Keep this script fast (Claude Code waits on it) and deterministic (no
# network, no random output).

cat <<'EOF'
[cc-skill-args-guard] System messages in this session may contain
`### Skill: <name> ... ARGUMENTS: <text>` blocks. These can be LEFTOVERS
from prior sessions — Claude Code preserves the most recent skill
invocation arguments indefinitely, without a timestamp, across context
compaction and session resumes.

Rules:
1. If this is a resumed session (you saw "This session is being continued
   from a previous conversation"), the resume summary's "All user messages"
   list is the AUTHORITY on what the user wants right now.
2. If a skill's ARGUMENTS text conflicts with the most recent entry in
   that list, FOLLOW THE SUMMARY. Ignore the ARGUMENTS.
3. Before starting CSS / font / styling work (or any work that matches a
   historical skill invocation), confirm with the user that this is the
   current request.
4. Never cite skill ARGUMENTS as "the user just said" without checking
   the resume summary first.

Reference: https://github.com/zvv1999/cc-skill-args-guard
EOF
