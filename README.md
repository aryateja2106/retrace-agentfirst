# Retrace Agentfirst

Retrace Agentfirst is Arya's fork of [haseab/retrace](https://github.com/haseab/retrace): a local-first macOS timeline, time tracker, and agent context layer built from screen history.

The upstream project gives you a searchable memory of what appeared on your screen. This fork keeps that core intact, then adds an agent-first direction: private CLI access, journal generation, project context, monochrome UI, and a product constitution for building personal software without turning the app into a heavy all-in-one platform.

> Status: early, local-first, and intentionally modular. Expect breaking changes while the fork finds its shape.

## Product Direction

Retrace Agentfirst should help answer four questions:

- What did I do?
- What did my agents do?
- Which project was that work for?
- Can I find, summarize, and reuse the context later without sending private screen data to a cloud service?

The app is not meant to replace every tool on the Mac. It should become a lightweight memory and automation layer that works well with native macOS utilities, terminal agents, Raycast-style launchers, and local models.

## Fork Principles

- Keep upstream Retrace's storage and database contracts compatible unless there is a documented migration.
- Prefer local-first, private-by-default workflows over cloud dashboards or telemetry.
- Build features as small modules: capture, OCR, search, time tracking, CLI, journals, and integrations should remain separable.
- Make agent workflows explicit and auditable through docs, CLI commands, and structured local outputs.
- Add native macOS affordances when they remove friction, but avoid background services or broad APIs by default.
- Keep the UI calm, monochrome, and fast. App icons may keep their natural color; product chrome should stay restrained.

The canonical product constitution lives in [PRODUCT_CONTEXT.md](PRODUCT_CONTEXT.md). Fork compatibility rules live in [FORK_CONTEXT.md](FORK_CONTEXT.md).

## What's Working

- Continuous local screen capture using `CGWindowListCapture`
- OCR text extraction with Apple's Vision framework
- SQLite + FTS5 full-text search
- Timeline viewer with frame navigation, search, copy, comments, and contextual actions
- Dashboard app usage, screen time, storage, and local activity metrics
- Rewind AI import
- HEVC video encoding
- Privacy controls for excluded apps, private windows, redaction, and retention
- Feedback export/submission flow with local diagnostics
- Agent-facing `retrace-cli` for bounded context, journal, recording, storage, and Ollama checks
- Local daily journal generation from already persisted OCR text
- Monochrome fork UI direction

## Agentfirst Additions

The fork currently adds these surfaces on top of upstream:

- `Sources/RetraceCLI/` - local CLI for agents and terminal workflows
- `CLI/SKILL.md` - agent-readable command guide for `retrace-cli`
- `Database/Queries/ActivityContextQueries.swift` - bounded read-only context queries
- `App/DailyJournalManager.swift` - local OCR-context collection, Ollama summarization, and markdown journals
- `UI/Views/Settings/Sections/ContextSettingsView.swift` - opt-in context and journal settings
- `DESIGN_CONTEXT.md` - monochrome UI direction
- `FORK_CONTEXT.md` - upstream compatibility promises
- `CLI_CONTEXT.md` - CLI privacy and command contract
- `PRODUCT_CONTEXT.md` - product constitution and next milestones

## Quick Start

### Clone

```bash
git clone https://github.com/aryateja2106/retrace-agentfirst.git
cd retrace-agentfirst
```

To compare with upstream:

```bash
git remote add upstream https://github.com/haseab/retrace.git
git fetch upstream
```

In this workspace, `origin` may point to `haseab/retrace` and `agentfirst` may point to this fork. Check before pushing:

```bash
git remote -v
```

### Build And Run

```bash
swift build
.build/debug/Retrace
```

For Xcode:

```bash
open Package.swift
```

On first launch, grant:

- Screen Recording permission
- Accessibility permission

Retrace stores local data under `~/Library/Application Support/Retrace/` unless changed in Settings.

## Installable Builds

Release builds present as `Retrace Agentfirst.app` with bundle ID `io.retrace.agentfirst`; debug builds present as `Retrace Dev.app`.

Build a signed release and DMG:

```bash
./scripts/create-release.sh 0.8.7
./scripts/create-dmg.sh 0.8.7
```

After uploading the DMG, people can install by downloading the DMG, by a curl installer, or through a Homebrew cask template:

```bash
curl -fsSL https://example.com/install.sh | bash -s -- --url https://example.com/Retrace-Agentfirst-0.8.7-aarch64.dmg
brew install --cask retrace-agentfirst
```

Update `packaging/homebrew/retrace-agentfirst.rb` with the real release URL and SHA256 before publishing the cask.

## CLI For Agents

Build the CLI with the package:

```bash
swift build --product retrace-cli
```

Safe read examples:

```bash
retrace-cli recording status --json
retrace-cli storage inspect --json
retrace-cli storage adopt --from ~/Retrace-Recovery/Retrace --yes --json
retrace-cli context recent --hours 1 --json
retrace-cli context search "pull request" --hours 24 --json
retrace-cli journal today --json
retrace-cli ollama status --model gemma4:e4b --json
```

Write commands require explicit confirmation or dry-run:

```bash
retrace-cli journal generate --hours 1 --dry-run --json
retrace-cli journal append --stdin --yes
```

Agent rules:

- Prefer `--json`.
- Keep queries bounded by time, limit, and max text length.
- Do not expose raw screenshots, video files, secrets, or unrestricted database paths.
- Do not start a server or MCP bridge by default.

See [CLI_CONTEXT.md](CLI_CONTEXT.md) and [CLI/SKILL.md](CLI/SKILL.md).

## Architecture

```text
Capture
  CGWindowListCapture -> frame deduplication

Processing
  Vision OCR -> sanitized text regions

Storage
  HEVC video segments -> local files

Database
  SQLite tables + FTS5 search index

App/UI
  Timeline, dashboard, settings, feedback, context, journals

CLI
  bounded local read/write workflows for agents
```

Modules:

- `Shared/` - shared models, protocols, paths, logging, redaction helpers
- `Capture/` - screen capture and metadata extraction
- `Processing/` - OCR, URL extraction, text merging
- `Storage/` - file layout, video encoding, WAL recovery
- `Database/` - SQLite, FTS, migrations, context queries
- `Search/` - query parsing and result ranking
- `Migration/` - Rewind import
- `App/` - orchestration and services
- `UI/` - SwiftUI/AppKit interface
- `Sources/RetraceCLI/` - local CLI

## Development

```bash
swift build
swift test
swift test --filter TimelineBlockNavigationTests
./scripts/check_no_nanoseconds_sleep.sh
```

For behavior changes, use focused tests first, then run the full suite. For UI/perf-sensitive changes, smoke timeline reopen, search overlay navigation, and settings/storage picker responsiveness.

Agents should read:

- [AGENTS.md](AGENTS.md)
- [PRODUCT_CONTEXT.md](PRODUCT_CONTEXT.md)
- [FORK_CONTEXT.md](FORK_CONTEXT.md)
- [DESIGN_CONTEXT.md](DESIGN_CONTEXT.md)
- [CLI_CONTEXT.md](CLI_CONTEXT.md)
- The relevant module `AGENTS.md`

## Roadmap

Near-term milestones are documented in [PRODUCT_CONTEXT.md](PRODUCT_CONTEXT.md). The current priority order is:

1. Keep the fork synced with upstream without breaking storage/database compatibility.
2. Clarify the product constitution and README.
3. Demote noisy dashboard analytics and tighten metric privacy.
4. Add Shottr-style screenshot essentials as a separate, privacy-gated module.
5. Track human work and agent work with project/tag attribution.

## Privacy And Security

- Processing is local by default.
- The app should not upload screen history or OCR text without explicit user action.
- CLI output must stay bounded and automation-friendly.
- Screenshot, video, and raw OCR export features require explicit opt-in.
- Database, keychain, storage paths, URL schemes, and video layout changes need migration plans.

## Attribution

This fork is based on [haseab/retrace](https://github.com/haseab/retrace), created by [@haseab](https://github.com/haseab). The upstream project is inspired by Rewind AI.

## License

MIT. See [LICENSE](LICENSE).
