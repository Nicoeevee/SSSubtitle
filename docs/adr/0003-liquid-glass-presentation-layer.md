---
status: accepted
---

# Use Liquid Glass as a bounded presentation layer

SSSubtitle will adopt `liquid_glass_easy` incrementally for the app shell, major panels, and selected floating or interactive controls, while keeping Flutter Material for text input, lists, chips, loading, reading surfaces, accessibility, and keyboard interaction; the controller, Rust subtitle core, and `flutter_rust_bridge` boundary remain unchanged. We choose an app-owned `AppGlass*` wrapper and token layer because `liquid_glass_easy` supplies a visual surface and control layer rather than a complete Material replacement, preserving a reversible migration path, isolating future package API changes, and limiting shader cost on Windows and Web.

## Considered options

- **Replace Flutter Material throughout the application:** Rejected because `liquid_glass_easy` does not provide the complete set of content and desktop interaction widgets that SSSubtitle needs, and a full replacement would unnecessarily couple business screens to a visual dependency.
- **Keep the existing Material UI only:** Rejected because it does not provide the intended Liquid Glass hierarchy for the application shell and major floating surfaces.
- **Use Liquid Glass behind an application-owned presentation layer:** Accepted because it gives SSSubtitle the desired visual treatment while keeping migration incremental and reversible.

## Consequences

- Glass is used for hierarchy and floating surfaces, not for every subtitle candidate, list item, or subtitle line.
- The subtitle preview keeps a high-contrast, substantially opaque reading surface.
- New feature code should depend on `AppGlass*` components and shared glass tokens rather than directly on `liquid_glass_easy`.
- Dependency introduction and each rollout step require Windows and Web interaction and performance validation; controller, Rust, and FRB behavior remain outside this visual migration.
