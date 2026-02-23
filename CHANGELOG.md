# Changelog

All notable changes to BuildingPlanner will be documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.2] — 2026-02-23

### Added
- **Wall Builder — fully implemented.** Clicking on a Shape marker in Wall Builder mode
  now creates a closed wall along the marker polygon outline.
- Wall texture selection via an embedded GridMenu in the sidebar (sourced from
  `WallTool.Controls["Texture"]`, same technique as AdditionalSearchOptions).
- Shadow and Bevel corner toggles for the generated wall.
- Wall texture and color are read from `WallTool` state at click time, so the selected
  wall type is always used without a separate confirm step.

### Changed
- Wall Builder section in the sidebar no longer requires a Marker ID — walls are placed
  by clicking directly on the Shape marker, consistent with Pattern Fill behaviour.

---

## [1.0.1] — 2026-02-23

### Fixed
- **Pattern Fill — broken mode after SelectTool round-trip.** `Disable()` previously
  reset `_active_mode` to `NONE`, so returning to the tool left the overlay ignoring
  clicks. `Enable()` now restores the mode from the UI `OptionButton` selector.
- **Pattern Fill — `is not part of the current tag set` warnings.** Textures were loaded
  with `no_cache=true`, producing a new `Texture` instance unknown to Dungeondraft's
  asset registry. SelectTool could not resolve the tag for the placed pattern shape.
  Changed to `no_cache=false` so the engine-cached instance is reused.

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
