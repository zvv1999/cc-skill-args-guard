# Upstream issue body — file at https://github.com/anthropics/claude-code/issues

**Title:** Stale skill invocation arguments leak across sessions after context compaction

---

## Summary

When a Claude Code session is resumed after context compaction, the system prompt still contains `### Skill: <name> ... ARGUMENTS: <text>` blocks from skills invoked in **prior sessions** (potentially days ago). These arguments carry no timestamp and never expire, so the model can mistake them for the current user request and silently resume abandoned work.

## Reproduction

1. On Day 1, in any project, invoke a skill with arguments:
   ```
   /frontend-design:frontend-design redo the top marquee
   ```
2. Continue working in the same session across multiple days, switching topics (e.g. move from styling to backend data work).
3. Trigger context compaction (long conversation, or explicit `/compact`).
4. Resume the session.

## Expected behavior

Skill invocation arguments should be identifiable as historical — either timestamped, expired after a session boundary / N hours, or clearly labeled as `[HISTORICAL]`.

## Actual behavior

`lastInvocationArgs` is preserved indefinitely in session memory and rendered into the system prompt on every request with no temporal marker. After compaction, the conversation history that originally contextualized the invocation is gone, leaving the arguments looking like a fresh request.

## Impact

The model silently resumes work on a topic the user abandoned days ago, ignoring the user's current post-compaction request. In our case the model redid CSS/font styling work that had been completed and rejected two days earlier, instead of continuing the current data task. The user had to interrupt and manually redirect — this happened twice in the same project because the stale arguments persisted across further compactions.

## Evidence

Transcript inspection at `~/.claude/projects/<project>/<session>.jsonl`:

- The offending `ARGUMENTS:` text appears as a `user` message **only on the original invocation day** (inside the `<command-args>` of the slash command).
- It does **not** appear in any `user` or `system` message after that day — confirming it lives in the system prompt itself.
- The system prompt is not stored in the transcript, so the injection can only be inferred from model behavior.
- It does appear repeatedly in assistant responses as the model cites "the user's current request", which is the behavioral fingerprint of the leak.

Confirmed with: Claude Code 2.1.91, model `glm-5.2` via Anthropic-compatible proxy, macOS Darwin 22.1.0. The bug is model-agnostic — any model receiving this system prompt is vulnerable.

## Suggested fixes

1. **Timestamp args**: store `{args, invokedAt}`, render `ARGUMENTS (invoked YYYY-MM-DD HH:MM):` in the system prompt so the model can judge freshness.
2. **Expire on session boundary**: drop `lastInvocationArgs` when a new session starts, or after N hours of inactivity.
3. **Label clearly**: prefix historical args with `[HISTORICAL — may not reflect the current request]`.
4. **Don't re-inject on compaction**: when compacting, omit skill args from the new system prompt unless the user re-invoked the skill in the post-compaction window.

## Workaround

Community workaround: https://github.com/zvv1999/cc-skill-args-guard — a `SessionStart` hook + `CLAUDE.md` rule that forces the model to cross-check skill ARGUMENTS against the resume summary before acting. This patches model behavior but does not fix the underlying leak.
