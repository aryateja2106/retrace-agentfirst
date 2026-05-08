---
title: Product Roadmap
status: approved-starting-point
audience:
  - product
  - engineering
  - agents
last_updated: 2026-05-07
---

# Product Roadmap

This roadmap captures the approved direction for the Retrace fork. It is durable planning context, not a promise that every item is ready for implementation.

Use this with the [agent roadmap index](AGENT_ROADMAP_INDEX.md), [product context](../PRODUCT_CONTEXT.md), [fork context](../FORK_CONTEXT.md), [design context](../DESIGN_CONTEXT.md), [CLI context](../CLI_CONTEXT.md), and relevant module `AGENTS.md` files.

## Product Direction

Retrace Agentfirst should become a local-first, privacy-first, agent-first macOS productivity layer. It complements Raycast-style command launchers and Obsidian-style markdown knowledge bases by adding private screen memory, OCR, app usage, local journals, time tracking, and agent context.

The app should make better use of data it already captures before adding broad new infrastructure. The default experience should stay lightweight: no always-on localhost API, no default MCP bridge, no cloud telemetry, and no raw screenshot/video/OCR exposure through agent workflows.

## Product Principles

- Local first: screen history, OCR, work logs, and model summaries start on-device.
- Privacy first: sensitive captured content needs explicit user action, redaction, and bounded outputs before sharing.
- Agent first: agents get predictable docs, CLI commands, JSON, local files, and structured reports.
- Upstream compatible: preserve storage, database, keychain, URL scheme, and video layout contracts unless a migration plan exists.
- Native when useful: prefer Apple-native UI, markdown rendering, screen capture, and local model integrations where they reduce complexity.
- Modular by default: calendar, issue reporting, local AI, action recording, and vector memory should remain separable workstreams.

## Current Foundation

The fork already has:

- Continuous local screen capture, Vision OCR, SQLite/FTS search, HEVC video storage, and Rewind import.
- Timeline/search UI, dashboard app usage and system monitor surfaces, settings, and feedback export/submission support.
- `retrace-cli` for bounded local context, journal, recording, storage, and Ollama checks.
- Daily markdown journal generation from persisted OCR context.
- Fork docs for product context, compatibility, design direction, and CLI privacy.

## Roadmap Phases

### Phase 0: Fork Clarity

Goal: make the fork understandable and safe for future agents and humans.

- Keep [README](../README.md), [AGENTS.md](../AGENTS.md), [PRODUCT_CONTEXT.md](../PRODUCT_CONTEXT.md), [FORK_CONTEXT.md](../FORK_CONTEXT.md), [DESIGN_CONTEXT.md](../DESIGN_CONTEXT.md), and [CLI_CONTEXT.md](../CLI_CONTEXT.md) aligned.
- Clarify fork remotes, dev/prod app identities, build links, updater expectations, and side-by-side app behavior.
- Preserve upstream compatibility as the default answer for storage, database, keychain, and video conflicts.
- Keep documentation free of one-off transcript details and secrets.

Exit signal: a new agent can understand what to build next without guessing which docs are canonical.

### Phase 1: Calendar + Time Tracker v1

Goal: turn captured screen and app usage into a useful daily time view.

- Build a day timeline that groups focused app time, active/idle periods, capture health, and project tags.
- Add calendar/day summaries that answer what happened, what changed, what was interrupted, and what should resume.
- Add Pomodoro support and work-log reminders as local opt-in workflows.
- Reuse existing frame timestamps, app metadata, OCR context, and daily metrics before adding new storage surfaces.
- Keep raw OCR and screenshots out of default summaries; use bounded excerpts and user-selected context.

Exit signal: a user can review the day, correct labels, and generate a useful private work log.

### Phase 2: Agent Work Logs + Markdown

Goal: make agent-written work logs readable, portable, and connected to the day.

- Continue writing journals and work logs as markdown so they remain portable to Obsidian or plain files.
- Add native markdown rendering for agent-written logs later using Swift Markdown or a similarly native approach.
- Attach work logs to days, projects, apps, terminal sessions, and agent runs without creating a hidden server.
- Keep edit/export flows explicit and local.

Exit signal: a user can read and navigate agent-authored logs in-app without losing the underlying markdown files.

### Phase 3: Local AI Telemetry + Evals

Goal: make local AI workflows observable enough to trust.

- Track local Ollama and future MLX availability, selected models, latency, failures, and resource usage.
- Use system monitor telemetry to understand CPU, memory, and battery impact during local model calls.
- Add lightweight local evals for journal quality, context quality, and retrieval usefulness before expanding model-heavy features.
- Avoid storing private prompt or OCR content in telemetry unless a policy and opt-in path are documented.

Exit signal: local AI features can be debugged and compared without exposing private captured data.

### Phase 4: Token Usage From Local CLI Transcripts

Goal: help users understand local agent cost and activity without reading private transcripts.

- Parse local CLI JSONL transcripts for token usage, model, session, tool-call counts, and timing metadata.
- Default to aggregate summaries; do not expose raw transcript text in dashboards or agent outputs.
- Connect token usage to work logs, projects, and calendar days.
- Keep transcript paths and private file paths redacted or summarized.

Exit signal: a user can see agent effort and token usage by day/project while transcript content stays private by default.

### Phase 5: Issue Reporting With Screen Evidence

Goal: make user-reported issues structured enough for agents to fix.

- Let users combine short screen recordings, voice notes, text notes, logs, and diagnostics into a local issue package.
- Shape generated reports around [AI_ISSUE_TEMPLATE.md](../AI_ISSUE_TEMPLATE.md): observed facts, expected behavior, repro steps, evidence, suspected area, acceptance criteria, and unknowns.
- Add redaction review before sharing any screenshot, video, OCR text, log excerpt, voice transcript, or path.
- Support local export first; remote submission stays explicit.

Exit signal: a user can produce a redacted, agent-fixable issue report without manually assembling evidence.

### Phase 6: Structured Screen Action Recording

Goal: turn observed workflows into reusable instructions while protecting private content.

- Record high-level screen actions, app/window context, commands, clicks, and timing as structured events where possible.
- Produce reusable instructions, checklists, or skills from redacted action traces.
- Keep raw screenshots and unrestricted OCR out of generated instructions unless the user explicitly selects them.
- Treat generated skills as drafts that require user review before reuse.

Exit signal: a repeated workflow can become a private reusable instruction set without leaking sensitive screen content.

### Phase 7: Multimodal Memory, Vector Store, and RAG

Goal: add semantic retrieval after the v1 foundations are trustworthy.

- Add text embeddings for bounded OCR excerpts, journal entries, issue reports, and work-log summaries.
- Stage image or multimodal embeddings only after redaction, retention, and storage cost policies are clear.
- Keep vector storage local by default and tied to the existing privacy model.
- Use RAG-style retrieval to improve search, daily summaries, issue reports, and project resumption.

Exit signal: semantic retrieval improves local workflows without weakening privacy or upstream compatibility.

## Backlog Seeds

These are seed cards, not full specs.

### Calendar + Time Tracker v1

- User value: review the day, label time blocks, run Pomodoro sessions, and receive work-log reminders.
- Starting data: frame timestamps, app/window metadata, browser URLs, capture health, daily metrics, comments, tags, and bounded OCR context.
- Privacy constraint: summaries should prefer metadata and short selected excerpts; no default raw OCR dump.
- First planning question: which day view should be useful before project-level rollups exist?

### Dev/Versioning Workflow

- User value: keep fork development safe while production Retrace remains usable.
- Starting data: current README fork instructions, build scripts, bundle/app display behavior, updater expectations, and git remotes.
- Compatibility constraint: app identity changes can affect storage roots, keychain, URL schemes, updater behavior, and user trust.
- First planning question: what exactly distinguishes `Retrace` from `Retrace Dev` in app name, bundle ID, storage, keychain, URL scheme, and releases?

### Local AI Telemetry

- User value: understand when local models are available, slow, failing, or affecting the machine.
- Starting data: `retrace-cli ollama status`, system monitor surfaces, daily metrics, and journal generation outcomes.
- Privacy constraint: telemetry should track model/runtime behavior, not private prompt or OCR contents by default.
- First planning question: which metrics are needed to debug local summarization without collecting sensitive text?

### Agent Markdown + Token Usage

- User value: read agent work logs in-app and understand local agent effort by day/project.
- Starting data: markdown journals, local CLI JSONL transcripts, project tags, app usage, and terminal context.
- Privacy constraint: aggregate transcript metadata first; raw transcript text is opt-in and redacted before display or export.
- First planning question: what is the smallest transcript summary that is useful without showing transcript content?

### Screen Recording Issue Reports + Redaction/Sharing

- User value: capture a bug once and hand agents a structured, evidence-backed report.
- Starting data: feedback diagnostics, logs, short screen recordings, voice notes, user text, and the issue template.
- Privacy constraint: redaction review is required before attachments or OCR excerpts leave local storage.
- First planning question: what local review UI lets users remove sensitive frames, words, paths, and voice transcript segments quickly?

## Deferred Ideas

- Always-on localhost API or MCP bridge by default.
- Cloud sync or remote telemetry.
- Unbounded OCR export to agents.
- Multimodal embeddings before redaction, retention, and storage cost policies are clear.
- Broad automation that mutates files or apps without explicit user approval.
