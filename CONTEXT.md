# Context Index

This file is a short map for humans and agents. It intentionally points to the canonical documents instead of duplicating their rules.

## Read Order

1. [README.md](README.md) - human product overview and setup.
2. [PRODUCT_CONTEXT.md](PRODUCT_CONTEXT.md) - product constitution, hard constraints, and milestones.
3. [AGENTS.md](AGENTS.md) - project-wide coding and agent rules.
4. [FORK_CONTEXT.md](FORK_CONTEXT.md) - upstream compatibility and fork-specific changed surfaces.
5. [DESIGN_CONTEXT.md](DESIGN_CONTEXT.md) - monochrome UI direction.
6. [CLI_CONTEXT.md](CLI_CONTEXT.md) - `retrace-cli` privacy and command contract.
7. `{Module}/AGENTS.md` - module-specific implementation rules.

## Current Fork Shape

Retrace Agentfirst is upstream Retrace plus:

- Agent-safe local CLI commands.
- Bounded OCR context queries.
- Local journal generation from persisted OCR text.
- Monochrome UI direction.
- Product rules for human-plus-agent time tracking and second-brain workflows.

## Non-Goals Right Now

- Always-on localhost server.
- Default MCP bridge.
- Cloud sync or telemetry.
- Screenshot/video export through agent tools without explicit opt-in.
- Database or storage migrations for branding-only changes.
