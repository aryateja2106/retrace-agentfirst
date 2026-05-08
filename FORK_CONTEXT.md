# Fork Context

This fork keeps Retrace's upstream data contract intact while adding Arya-specific agent and journal features.

## Compatibility Promises

- Do not rename or reshape `retrace.db` tables, frame IDs, segment IDs, video rows, or `doc_segment`/`searchRanking` relationships.
- Do not change the default storage root, video segment layout, Keychain service/account, or database encryption semantics without an explicit migration plan.
- Rebrand surfaces are presentation-first: SwiftUI colors, app display metadata, icons, settings chrome, docs, and the fork bundle identity.
- The branded release app identity is `Retrace Agentfirst` / `io.retrace.agentfirst`; the debug app identity is `Retrace Dev` / `io.retrace.app.dev`.
- Storage, defaults, and keychain compatibility intentionally remain on the upstream-compatible `io.retrace.app` suite/services unless a later migration explicitly moves them.
- Context and journal features must read already-persisted sanitized OCR text. They must not decode screenshots or videos in the first milestone.
- Local journal markdown is additive and lives outside the core database/video store.

## Changed Surfaces

- `Sources/RetraceCLI/` adds the agent-facing CLI.
- `Database/Queries/ActivityContextQueries.swift` adds bounded read-only context queries.
- `App/DailyJournalManager.swift` adds low-impact collection, Ollama summarization, and markdown writing.
- `UI/Views/Settings/Sections/ContextSettingsView.swift` adds opt-in context/journal settings.
- `UI/Components/AppTheme.swift` and `UI/Components/MilestoneCelebrationManager.swift` enforce the fork's monochrome token system across dashboard, settings, timeline/search chrome, menus, and milestone surfaces.
- `PRODUCT_CONTEXT.md`, `CONTEXT.md`, `CLAUDE.md`, and `SKILLS.md` document the agent-first product constitution and host-tool entrypoints.

## Pulling Upstream

When pulling Hasib's upstream changes:

1. Resolve storage/database conflicts in favor of upstream unless a documented fork migration exists.
2. Keep fork additions additive and isolated behind new files, settings keys, or UI tabs.
3. Re-run the compatibility smoke check: upstream Retrace should still be able to open the same database and videos.
4. Re-run `retrace-cli context recent --json` after the app has recorded OCR data.

## Non-Goals For This Milestone

- No always-on localhost API.
- No MCP server by default.
- No VLM or screenshot-to-model summarization.
- No package scanner automation.
- No direct Obsidian API integration beyond markdown folder compatibility.
