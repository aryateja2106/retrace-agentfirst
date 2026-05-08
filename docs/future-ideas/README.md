---
title: Future Ideas
status: raw
type: future-ideas-index
owner: user-originated
priority: untriaged
privacy: local-first
last_updated: 2026-05-07
---

# Future Ideas

This folder is a durable intake area for raw Retrace product ideas. These notes are not accepted implementation specs, roadmap commitments, or architectural decisions.

Use this folder when an idea should survive the current chat but still needs triage, privacy review, design work, and an implementation plan before code changes begin.

## Backlinks

- [Agent roadmap index](../AGENT_ROADMAP_INDEX.md)
- [Product roadmap](../PRODUCT_ROADMAP.md)
- [Root agent guide](../../AGENTS.md)
- [Product context](../../PRODUCT_CONTEXT.md)
- [Design context](../../DESIGN_CONTEXT.md)
- [CLI context](../../CLI_CONTEXT.md)

## How Future Agents Should Use This Folder

1. Treat every item here as raw and unprioritized unless another canonical roadmap document says otherwise.
2. Compare the idea against [Product Context](../../PRODUCT_CONTEXT.md) before planning.
3. Preserve local-first privacy defaults, especially for screenshots, videos, OCR text, transcripts, paths, and voice.
4. Split one idea into a scoped plan before implementation.
5. Keep implementation details out of this folder unless they are useful constraints for future planning.

## Dedicated Idea Notes

| Idea | Status | Summary |
| --- | --- | --- |
| [Digital Pet Quick-Notes Companion](digital-pet-quick-notes-companion.md) | Raw | Codex-like on-screen companion that follows the user and collects temporary task notes for future agent sessions. |

## Raw Idea Index

These ideas came from user brainstorming and should stay clearly labeled as raw until promoted into a scoped roadmap item.

| Idea | Raw Direction | Related Roadmap Thread |
| --- | --- | --- |
| Calendar/day time tracking view | A Toggl Track-like day view showing where time went across apps, projects, focus blocks, and interruptions. | Calendar + Time Tracker v1 |
| Pomodoro timer and work-log reminders | Local reminders and Pomodoro support that help users log work and resume tasks. | Calendar + Time Tracker v1 |
| AI-native macOS productivity layer | Position Retrace as a local-first companion to Raycast and Obsidian for human-plus-agent work. | Product Direction |
| Native markdown rendering | Render agent-written logs and notes in-app with Swift Markdown or another native approach later. | Agent Markdown + Token Usage |
| Dev/prod versioning workflow | Clarify production vs development app identities, build workflows, update links, and fork links. | Dev/Versioning Workflow |
| Local AI/Ollama/MLX telemetry | Track local model availability, latency, CPU, memory, failures, and evaluation results without cloud telemetry. | Local AI Telemetry |
| Agent token usage tracking | Parse Claude Code, Codex, Gemini, Cursor, and similar JSONL transcripts for OpenUsage-like aggregate stats. | Agent Markdown + Token Usage |
| Issue reporting from evidence | Turn screen recordings, voice, text, logs, and structured diagnostics into agent-fixable issue reports. | Issue Reports + Redaction |
| Structured screen-action recording | Capture redacted workflows as structured actions that can become reusable instructions or skills. | Screen Action Recording |
| Redaction/photo-edit UI | Let users censor sensitive regions, frames, words, paths, and transcript segments before sharing. | Issue Reports + Redaction |
| Demo/help screen recording | Record shareable demos or help requests with optional face/camera overlay. | Issue Reports + Redaction |
| Multimodal memory and RAG | Add document/screen embeddings, local vector storage, and RAG-style retrieval after privacy foundations are ready. | Multimodal Memory |
| Secure multi-device sync | Explore local-first, privacy-preserving sync or device connection as a later direction. | Deferred / Later Direction |

## Promotion Checklist

Before moving an idea from this folder into an implementation plan, answer:

- What user workflow does this improve?
- What existing captured data can it reuse before adding new sensors or stores?
- What sensitive data could it expose?
- What local-first default keeps the feature useful without cloud dependencies?
- Which module docs and tests would future implementers need to read?
