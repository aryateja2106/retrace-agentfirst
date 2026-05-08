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
retrace-cli storage audit --include-defaults --manifest ~/Desktop/retrace-recovery-manifest.json
retrace-cli storage export --to ~/Retrace-Portable-Export --yes --json
retrace-cli ollama status --model gemma4:e4b --json
```

## Design Contract

- Context commands open `retrace.db` through `SQLiteReadOnlyConnectionFactory`.
- Context sampling is bounded by time range, frame limit, and text length.
- Journal generation uses completed OCR text only, then writes markdown sections to the configured folder.
- `storage audit` emits privacy-safe recovery manifests with file metadata, table counts, Rewind cutoff diagnostics, and no raw OCR/screenshot payloads.
- `storage export` copies local databases, WAL/SHM sidecars, chunk folders, non-secret settings, a README, and `manifest.json`; it requires `--yes`.
- MCP tools, if added later, should be thin wrappers over these commands rather than a broader data API.
