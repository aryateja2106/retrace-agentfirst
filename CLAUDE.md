# Claude Guide

Claude and Claude Code should use the same canonical instructions as every other agent.

## Start Here

1. Read [AGENTS.md](AGENTS.md).
2. Read [PRODUCT_CONTEXT.md](PRODUCT_CONTEXT.md).
3. Read [FORK_CONTEXT.md](FORK_CONTEXT.md), [DESIGN_CONTEXT.md](DESIGN_CONTEXT.md), and [CLI_CONTEXT.md](CLI_CONTEXT.md) when the task touches fork behavior, UI, or agent CLI workflows.
4. Read the relevant `{Module}/AGENTS.md` before editing module code.

## Important Rules

- Preserve upstream database, storage, keychain, URL scheme, and video layout contracts.
- Keep fork additions additive and modular.
- Do not expose raw screenshots, videos, secrets, or unrestricted OCR text through agent workflows.
- Prefer focused tests and full `swift test` before promoting changes.
- Update [AGENTS.md](AGENTS.md) when files, directories, or module structure change.

This file is a thin compatibility pointer. Do not duplicate project policy here.
