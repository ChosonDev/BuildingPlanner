# Changelog

All notable changes to BuildingPlanner will be documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.0] — 2026-02-23

### Added
- **Pattern Fill** — click on any Shape marker to fill its interior with the selected
  Dungeondraft terrain pattern. Supports custom color, rotation (0–360°), layer (0–9),
  and optional outline. Pattern selection via an embedded GridMenu in the sidebar.
- **Wall Builder** *(stub)* — UI scaffolding in place; implementation coming in a future release.
- **Mirror Mode** *(stub)* — UI scaffolding in place; implementation coming in a future release.
- Sidebar tool panel with mode selector (Pattern Fill / Wall Builder / Mirror Mode).
- Full integration with [GuidesLines](https://github.com/ChosonDev/GuidesLines) API
  (`compute_fill_polygon`, `get_marker`, marker type checks).
- Input overlay node for intercepting world-canvas clicks without conflicting with
  Dungeondraft's built-in tools.
- Logger, History stubs, and `BuildingPlannerUtils` geometry helpers.
