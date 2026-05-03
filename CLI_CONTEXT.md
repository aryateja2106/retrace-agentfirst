# CLI Context

`retrace-cli` is the safe local interface for coding agents and terminal workflows.

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
retrace-cli ollama status --model gemma4:e2b --json
```

## Design Contract

- Context commands open `retrace.db` through `SQLiteReadOnlyConnectionFactory`.
- Context sampling is bounded by time range, frame limit, and text length.
- Journal generation uses completed OCR text only, then writes markdown sections to the configured folder.
- MCP tools, if added later, should be thin wrappers over these commands rather than a broader data API.
