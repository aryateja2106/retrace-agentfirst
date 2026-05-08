---
name: retrace-cli
description: Use the local Retrace CLI for private, agent-safe context access and journal workflows.
---

# Retrace CLI

Use `retrace-cli` when an agent needs local Retrace context. Prefer JSON output.

## Safe Read Commands

```bash
retrace-cli context recent --hours 1 --json
retrace-cli context search "query" --hours 24 --json
retrace-cli journal today --json
retrace-cli recording status --json
retrace-cli storage inspect --json
retrace-cli storage audit --include-defaults --json
retrace-cli ollama status --model gemma4:e4b --json
```

## Write Commands

Write commands are explicit and local:

```bash
retrace-cli journal append --stdin --yes
retrace-cli journal generate --hours 1 --dry-run --json
retrace-cli journal generate --hours 1 --yes --json
retrace-cli storage export --to ~/Retrace-Portable-Export --yes --json
retrace-cli storage adopt --from ~/Retrace-Recovery/Retrace --yes --json
```

## Privacy Rules

- Do not start a server or MCP bridge.
- Do not request raw screenshots or video files.
- Do not print secrets or full private paths in summaries.
- Use `--dry-run` before generation when testing a new model or prompt.
- Use `storage audit` before moving data out of Trash or App Support.
- `storage export` copies databases and chunk folders but never Keychain secrets; treat the destination as private local data.
- `storage adopt` does not copy or delete data; it changes the active app data folder and requires an app restart.
