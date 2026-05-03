# Skills Guide

Retrace Agentfirst currently exposes one repo-local agent skill:

- [CLI/SKILL.md](CLI/SKILL.md) - safe `retrace-cli` usage for local context and journal workflows.

## Skill Policy

- Skills should wrap deterministic local commands before prompts.
- Skills should prefer JSON output and bounded reads.
- Skills must not request raw screenshots, videos, secrets, or unrestricted OCR output by default.
- New skills should point back to [PRODUCT_CONTEXT.md](PRODUCT_CONTEXT.md), [CLI_CONTEXT.md](CLI_CONTEXT.md), and [AGENTS.md](AGENTS.md) instead of duplicating policy.

This root file is an index for tools that look for `SKILLS.md`. The canonical executable skill remains [CLI/SKILL.md](CLI/SKILL.md).
