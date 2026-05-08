---
title: Digital Pet Quick-Notes Companion
status: raw
type: future-idea
owner: user-originated
priority: untriaged
privacy: local-first
last_updated: 2026-05-07
---

# Digital Pet Quick-Notes Companion

This is a raw future idea, not an accepted implementation spec.

## Idea

Add a Codex-like on-screen digital pet or companion for Retrace. The companion can be opened or closed, follows the user on screen, and acts as a friendly capture surface for quick thoughts while work is in motion.

## User Workflow

When a user is juggling multiple tasks, they can dump thoughts, todos, reminders, or rough context into the pet without deciding where each note belongs yet.

For now, these entries should behave like temporary quick notes:

- Fast to capture.
- Local by default.
- Easy to review later.
- Safe to ignore or delete.
- Separate from accepted journals, roadmap items, and issue reports until the user promotes them.

When the user starts a new agent session, they can select relevant quick notes or tasks from the stash and give them to the agent as context.

## Product Fit

The companion could make Retrace feel more agent-native without requiring a broad background API. It fits the local-first direction if the stash remains on-device and user-selected notes are the only content handed to agents.

It also creates a softer entry point for capturing messy thoughts before they become structured work logs, issues, plans, or roadmap items.

## Privacy Notes

- Do not expose note contents to agents by default.
- Do not attach screenshots, OCR, paths, or transcripts automatically.
- Keep handoff explicit: the user chooses which notes enter an agent session.
- Treat the stash as private local working memory until promoted or exported.

## Open Questions

- Is the companion a menu bar popover, floating window, desktop overlay, or optional pet layer?
- How should the user open, close, pause, or hide it?
- Should notes be plain markdown, structured tasks, or both?
- How long should temporary quick notes persist before review or cleanup?
- Which existing journal, CLI, or settings surfaces should eventually expose the stash?
- What daily metrics are appropriate if this becomes a real feature?

## Possible First Planning Pass

A future implementation plan should start by defining the smallest useful capture loop:

1. Open the companion.
2. Add a quick note.
3. Review the stash.
4. Select one or more notes for agent context.
5. Delete or promote handled notes.

Do not implement this from the raw idea alone. Promote it into a scoped plan first.
