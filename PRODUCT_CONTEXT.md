# Product Context

This is the product constitution for Retrace Agentfirst. It defines what the fork is optimizing for, what must stay stable, and which milestones should come next.

## North Star

Retrace Agentfirst is a local-first second brain for human-plus-agent work on macOS.

It should help Arya inspect real work over time: focused human interaction, background agent activity, project context, searchable screen memory, and local journals. The app should work with terminals, Claude Code, Codex, Cursor, Raycast-style launchers, Apple-native utilities, and local models without becoming a server or a cloud product by default.

## Product Principles

1. Local first. Screen history, OCR, journals, and summaries start on-device.
2. Privacy by default. Raw screenshots, videos, OCR text, and private paths are never exposed casually.
3. Modular by design. Features should fit into clear surfaces: capture, processing, storage, database, search, app coordination, UI, and CLI.
4. Upstream compatible. Keep Hasib's Retrace data contracts intact unless a migration is explicit.
5. Agent readable. Important workflows need predictable CLI, JSON, docs, and bounded outputs.
6. Apple native when useful. Prefer native macOS capabilities before custom infrastructure.
7. Lightweight first. Performance, memory, and battery costs should block flashy but heavy features.
8. Personal before generic. Build the workflows Arya actually uses, then generalize only when the shape is stable.

## Hard Constraints

- Do not rename or reshape core database tables, frame IDs, segment IDs, video rows, `doc_segment`, or `searchRanking` without a migration plan.
- Do not change default storage roots, video segment layout, keychain identifiers, encryption semantics, URL schemes, or bundle identifiers without documenting migration and updater impact.
- Do not add an always-on localhost API, MCP bridge, or background server by default.
- Do not pipe raw screenshots, videos, or unrestricted OCR output through CLI or Raycast without explicit opt-in and bounded controls.
- Do not perform blocking SQLite, file, image decode, OCR, capture, or metadata work on the main thread.
- Do not add dashboard metrics that store sensitive raw content unless the product value justifies it and the metadata policy is documented.
- Do not let fork UI changes make upstream merges difficult for purely aesthetic reasons.

## Current Product Surfaces

- Timeline: searchable screen memory, frame navigation, copy/save, comments, tags, in-frame search, and deeplinks.
- Dashboard: app usage, screen time, storage, recording health, feedback, and system monitor views.
- Settings: capture, storage, privacy, context/journals, power, tags, advanced tools.
- CLI: bounded local context, journal, recording, storage, and Ollama commands.
- Journals: markdown summaries generated from already persisted OCR context.
- Voice: initial local dictation surface with editable overlay and settings; transcription backend integration is the next step when absent.
- Obsidian/local notes: markdown-folder-first output that can be opened by Obsidian or any local editor, with CLI as an optional helper.
- Feedback: local diagnostic export and optional submission.

## Human Time And Agent Time

The fork should distinguish at least two kinds of work:

- Human active time: mouse, keyboard, focused apps, and visible project context.
- Agent work time: terminal agents, background tasks, CLI invocations, generated changes, and project-tagged outcomes.

The long-term target is a project view that can answer:

- What did I work on today?
- Which agents worked in the background?
- What files, apps, windows, and commands were involved?
- What changed, what failed, and what should I resume?

## Integration Direction

Preferred integration layers:

- `retrace-cli` for terminal agents and deterministic automation.
- `retrace://` deeplinks for UI navigation.
- Raycast or native launcher scripts as thin wrappers over CLI/deeplinks.
- Markdown journals and folders for portable output.
- Obsidian-compatible folders as plain markdown destinations, not a required plugin or database integration.
- Local model calls through explicit settings and dry-run paths.

Avoid broad hidden APIs until repeated workflows prove they need them.

## Next Milestones

### 1. Fork Documentation And Branch Hygiene

- Keep `agentfirst/main` synced with upstream plus fork commits.
- Keep `README.md`, `AGENTS.md`, `FORK_CONTEXT.md`, `DESIGN_CONTEXT.md`, `CLI_CONTEXT.md`, and this file aligned.
- Fix broken documentation references when found.

### 2. Dashboard Cleanup And Metric Privacy

- Demote or hide low-value counters such as timeline opens, searches, and text copies from the default dashboard.
- Keep screen time, storage, app usage, and recording health prominent.
- Stop storing raw search query and copied text metadata unless explicitly needed.
- Preserve `daily_metrics` as a local operations ledger, but make sensitive metadata opt-in or summarized.

### 3. Shottr Replacement Essentials

- Add a privacy-gated screenshot module for capture screen, capture window, capture area, and copy to clipboard.
- Reuse existing CoreGraphics capture, pasteboard, and Vision OCR paths where possible.
- Add OCR-to-clipboard as a user action, not an agent default.
- Expose Raycast-friendly commands only after output and privacy policy are explicit.

### 4. Agent Work Tracking

- Instrument `retrace-cli` invocations and agent-related workflows.
- Add project/tag attribution for terminal sessions, windows, and journal entries.
- Build views that separate human active time from background agent time.
- Prefer explicit tags and local heuristics before model-heavy classification.

### 5. Second Brain Views

- Improve project-level search and summaries.
- Connect journals, comments, tags, app sessions, and screenshots into a resumable work narrative.
- Keep exports portable as markdown and local files.

### 6. Voice MVP

- Start with local dictation UI: editable overlay, settings, and privacy boundaries.
- Wire the actual transcription backend only after the surface and local-model configuration are explicit.
- Keep generated voice notes portable as markdown when persisted.

## Regression Policy

- Build and test before promotion: `swift build`, `swift test`, and focused tests for touched surfaces.
- Run `scripts/check_no_nanoseconds_sleep.sh` for concurrency guardrails.
- For UI/perf-sensitive work, smoke timeline reopen, search overlay navigation, and settings/storage picker flows.
- For fork-specific CLI changes, verify JSON output and privacy bounds.
- For upstream pulls, prefer upstream behavior for database/storage conflicts unless a fork migration exists.
