# Design Context

This fork moves Retrace toward a monochrome, Notion/Linear-inspired UI while keeping upstream interaction structure intact.

## Direction

- Prefer black, white, and neutral gray surfaces.
- Keep high contrast, calm spacing, and restrained motion.
- Use one monochrome accent token instead of introducing new brand colors per feature.
- Use matte graphite panels, subtle hairline borders, and restrained shadows instead of glassy blue glow.
- Let app icons carry natural app color; keep product chrome monochrome except muted semantic danger/warning states.
- Preserve existing SwiftUI screens and component boundaries so upstream merges stay manageable.

## Current Theme Surface

- `SettingsDefaults.colorTheme` defaults to `monochrome`.
- `MilestoneCelebrationManager.ColorTheme.monochrome` is the isolated theme selector.
- `Color.retraceDeepBlue`, `Color.retraceCard`, `Color.retraceSecondaryColor`, and related semantic colors are now neutralized.
- Feature-specific gradients still exist for compatibility, but they resolve to neutral ramps in fork UI.
- `RetraceMenuStyle`, settings tabs, dashboard cards, timeline/search chrome, and metric surfaces should route through `AppTheme.swift` tokens rather than literal blue/green/orange accents.

## Do Not Change Without A Migration Plan

- Database schema or storage paths for branding reasons.
- UserDefaults keys that affect database/storage compatibility.
- Keychain service or account identifiers.
- URL schemes or bundle IDs until app migration and updater implications are documented.
