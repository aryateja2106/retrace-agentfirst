# CLI Context

`retrace-cli` is the safe local interface for coding agents and terminal workflows.

Obsidian support is markdown-folder-first. Agents should treat the configured journal or notes folder as the integration point, and use `retrace-cli` only when bounded reads, appends, generation, or status checks are helpful.

## Privacy Rules

- Prefer read-only commands.
- Do not start background servers.
- Do not expose API keys, raw screenshot files, or unrestricted database paths in command output.
- Use `--json` for agent workflows.
- Write commands require explicit confirmation with `--yes` unless `--dry-run` is used.

## Commands

```bash
retrace-cli context recent --hours 1 --json
retrace-cli context search "pull request" --hours 24 --json
retrace-cli journal today --json
retrace-cli journal day --date 2026-05-02 --json
retrace-cli journal append --stdin --yes
retrace-cli journal generate --hours 1 --dry-run --json
retrace-cli recording status --json
retrace-cli storage inspect --json
retrace-cli ollama status --model gemma4:e4b --json
```

## Design Contract

- Context commands open `retrace.db` through `SQLiteReadOnlyConnectionFactory`.
- Context sampling is bounded by time range, frame limit, and text length.
- Journal generation uses completed OCR text only, then writes markdown sections to the configured folder.
- Obsidian/local notes workflows write normal markdown files first; the CLI is optional and should not assume an Obsidian plugin, database, or running app.
- Local model checks are explicit status/generation workflows, not a hidden server contract.
- Voice MVP docs refer to the initial local dictation overlay/settings surface; transcription backend wiring is a separate follow-up unless implemented in the current build.
- MCP tools, if added later, should be thin wrappers over these commands rather than a broader data API.
