---
title: Agent Roadmap Index
status: approved-starting-point
audience:
  - agents
  - maintainers
last_updated: 2026-05-07
---

# Agent Roadmap Index

This is the first stop for agents planning fork product work. It points to durable source documents, names the active roadmap threads, and keeps backlog seeds short enough to stay useful.

This index is not an implementation spec. Before changing code, read the relevant module docs and write or follow a scoped plan.

## Canonical Reading Order

1. [Root agent guide](../AGENTS.md) - project rules, module boundaries, test policy, and privacy constraints.
2. [Product context](../PRODUCT_CONTEXT.md) - product constitution, hard constraints, and current milestones.
3. [Product roadmap](PRODUCT_ROADMAP.md) - approved product direction and staged backlog seeds.
4. [Fork context](../FORK_CONTEXT.md) - upstream compatibility promises and changed fork surfaces.
5. [Design context](../DESIGN_CONTEXT.md) - monochrome UI direction and design constraints.
6. [CLI context](../CLI_CONTEXT.md) and [CLI skill](../CLI/SKILL.md) - agent-safe local CLI contract.
7. [AI issue template](../AI_ISSUE_TEMPLATE.md) - structured bug report format for agent-fixable issues.
8. Relevant module docs: [Database](../Database/AGENTS.md), [UI](../UI/AGENTS.md), [App](../AGENTS.md#project-structure), [Capture](../Capture/AGENTS.md), [Processing](../Processing/AGENTS.md), [Search](../Search/AGENTS.md), [Storage](../Storage/AGENTS.md), and [Migration](../Migration/AGENTS.md).

## Product Frame

Retrace Agentfirst is a local-first, privacy-first, agent-first macOS productivity app. It should complement tools like Raycast and Obsidian rather than replace them:

- Raycast-style usage: fast launch actions, status checks, and explicit user-triggered workflows.
- Obsidian-style usage: portable markdown journals, work logs, and long-lived local notes.
- Retrace-specific value: private screen memory, OCR, app usage, time tracking, issue evidence, and agent context from data already captured on the Mac.

Default posture: no cloud telemetry, no always-on localhost API, no default MCP bridge, and no raw screenshot, video, or unrestricted OCR exposure through agent workflows.

## What Exists

- Screen capture, OCR, SQLite/FTS search, HEVC storage, timeline/search UI, dashboard metrics, feedback export, and Rewind import.
- Agent-facing `retrace-cli` for bounded context, journal, recording, storage, and Ollama checks.
- Local daily journal generation from persisted OCR context.
- Monochrome fork UI direction and fork compatibility docs.
- Early system monitor and daily metrics surfaces.

## Roadmap Threads

| Thread | Goal | Primary Docs | Likely Modules |
| --- | --- | --- | --- |
| Calendar + Time Tracker v1 | Turn screen/app activity into a useful day view with reminders and Pomodoro support. | [Product roadmap](PRODUCT_ROADMAP.md), [Product context](../PRODUCT_CONTEXT.md) | `App/`, `Database/`, `UI/`, `Sources/RetraceCLI/` |
| Dev/Versioning Workflow | Keep fork, dev, and production builds clear and usable side by side. | [Fork context](../FORK_CONTEXT.md), [README](../README.md) | `UI/`, scripts, docs |
| Local AI Telemetry | Track local Ollama/MLX/system monitor state for reliability and evaluation. | [CLI context](../CLI_CONTEXT.md), [Product roadmap](PRODUCT_ROADMAP.md) | `App/`, `UI/`, `Sources/RetraceCLI/` |
| Agent Markdown + Token Usage | Render agent-written work logs natively and summarize local CLI JSONL token use. | [CLI skill](../CLI/SKILL.md), [Product roadmap](PRODUCT_ROADMAP.md) | `App/`, `UI/`, `Sources/RetraceCLI/` |
| Issue Reports + Redaction | Capture screen recording, voice, text, and diagnostics into structured reports. | [AI issue template](../AI_ISSUE_TEMPLATE.md), [Fork context](../FORK_CONTEXT.md) | `UI/`, `App/`, `Storage/` |
| Screen Action Recording | Convert privacy-filtered interactions into reusable instructions or skills. | [Product roadmap](PRODUCT_ROADMAP.md), [Design context](../DESIGN_CONTEXT.md) | `Capture/`, `Processing/`, `App/`, `UI/` |
| Multimodal Memory | Add embeddings, vector store, and RAG-style retrieval after v1 foundations are stable. | [Product context](../PRODUCT_CONTEXT.md), [Search docs](../Search/AGENTS.md) | `Search/`, `Processing/`, `Database/` |

## Privacy Guardrails

- Prefer summaries, metadata, and explicit user-selected excerpts over raw captured content.
- Keep redaction before sharing, issue reporting, skill generation, or model handoff.
- Treat screenshots, videos, OCR text, private paths, API keys, and local transcript content as sensitive.
- Preserve upstream database, storage, keychain, URL scheme, and video layout contracts unless a migration is planned and documented.
- Use bounded CLI outputs for agents. Do not add broad hidden APIs before repeated workflows prove they are needed.

## Backlog Seed Index

These seeds are intentionally short. Expand each into an implementation plan only after reading the relevant module docs.

### Calendar + Time Tracker v1

- Build a day calendar from app focus, screen activity, capture health, and user-labeled work blocks.
- Add Pomodoro sessions and work-log reminders as local, opt-in productivity helpers.
- Prefer existing screen/OCR/app usage data before adding new sensors or schemas.

### Dev/Versioning Workflow

- Clarify dev vs production app names, build links, branch names, and release/update expectations.
- Keep `Retrace` and `Retrace Dev` usable side by side.
- Document any bundle ID, URL scheme, keychain, or updater change before implementation.

### Local AI Telemetry

- Track Ollama/MLX availability, selected model, latency, failures, and system resource impact.
- Keep model telemetry local and separate from private captured content.
- Add lightweight eval hooks for journal/context quality before model-heavy features expand.

### Agent Markdown + Token Usage

- Render agent-written markdown work logs natively in the app using Swift Markdown later.
- Parse local CLI JSONL transcripts for token usage and session summaries without exposing transcript text by default.
- Connect token and work-log summaries to projects, days, and agents.

### Screen Recording Issue Reports + Redaction/Sharing

- Let users report issues with short screen recordings, voice notes, text, logs, and diagnostics.
- Produce reports shaped like [AI_ISSUE_TEMPLATE.md](../AI_ISSUE_TEMPLATE.md) so agents can fix them.
- Add redaction and sharing controls before any attachment leaves local storage.
