# Changelog

All notable changes to BuildingPlanner will be documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.9] — 2026-02-25

### Fixed
- **Pattern color picker now shows the default color for the selected pattern.**
  Uses `PatternShapeTool.GetDefaultColor(texture)` — the pattern equivalent of
  `WallTool.GetWallColor(texture)`.

---

## [1.0.8] — 2026-02-25

### Fixed
- **Wall color picker now shows the default color for the selected wall style.**
  When a wall texture is selected in the Wall Builder or Room Builder panel, the
  color picker automatically updates to the style's default color via
  `WallTool.GetWallColor(texture)`. Previously the picker always showed white
  regardless of the chosen style.
- **Wall color is correctly applied from the first click.** The default color is
  read and propagated to `WallBuilder.active_color` when the grid menu is first
  built, so walls are no longer placed with white when the user has not manually
  changed the color.

---

## [1.0.7] — 2026-02-25

### Fixed
- **Merge mode now cleans up `absorbed_marker_ids`.** Fills and walls belonging
  to markers that were consumed (deleted) during `place_shape_merge` are removed
  from the scene before new objects are placed.
- **MarkerObjectRegistry is no longer reset on tool switch.** `on_disabled()` is
  no longer called from `BuildingPlannerTool.Disable()`, so the marker→objects
  mapping survives Disable/Enable cycles and Merge mode can still clean up stale
  objects after returning from another tool.
- **Pattern and wall selections persist across tool switches.** `PatternPanel` and
  `WallPanel` now save the selected item index before tearing down the grid menu
  and restore it when the menu is rebuilt on the next Enable.

---

## [1.0.6] — 2026-02-25

### Added
- **Room Builder sub-modes: Single and Merge.** A new `OptionButton` in the Room
  Builder UI lets the user choose between two placement behaviours:
  - **Single** — existing behaviour: place a temporary Shape marker, fill it with
    the selected pattern and wall, then delete the marker.
  - **Merge** — calls `GuidesLinesApi.place_shape_merge()` to union the virtual
    shape with every overlapping existing Shape marker; fills and walls are placed
    on each resulting merged polygon. Requires GuidesLines v2.2.5+. Falls back to
    Single (keeping the marker) when there are no overlapping markers.
- **MarkerObjectRegistry** (`scripts/features/MarkerObjectRegistry.gd`).
  Tracks the association between GuidesLines marker ids and the pattern fills /
  walls created for them. In Merge mode, stale fills and walls from superseded
  markers are removed from the scene before new ones are placed.

### Changed
- `RoomBuilder._build_room_single_impl` — in the fallback «keep marker» path the
  early-error branch no longer deletes the marker when `delete_marker_after` is
  false.
- `BuildingPlannerTool.Disable()` now calls `_room_builder.on_disabled()` to
  purge the `MarkerObjectRegistry` on tool switch.

---

## [1.0.5] — 2026-02-24

### Added
- **Grid snap support for Room Builder.** Click position is now snapped to the
  grid when Dungeondraft snapping is enabled (`Editor.IsSnapping`). Supports the
  optional **Lievven.Snappy_Mod** for custom snap intervals (detected once at map
  load via `ModRegistry`, same pattern as GuidesLines).
- **Wall color picker.** `WallPanel` (UI) and `WallBuilder` / `RoomBuilder`
  (features) now expose an independent color setting for walls, replacing the
  previous read of `WallTool.Color` at click time.

### Removed
- **Mirror Mode** — feature stub and all related code removed (UI section,
  `MirrorMode.gd`, `MirrorPlacementRecord`, `execute_mirror_toggle()`).

### Refactored
- `BuildingPlannerToolUI` split into two reusable inner classes **`PatternPanel`**
  and **`WallPanel`**, eliminating duplicated grid-menu factory code that existed
  separately for Pattern Fill, Wall Builder, and Room Builder sections.

---

## [1.0.4] — 2026-02-24

### Added
- **Room Builder mode.** New tool mode that creates a complete room in one click:
  fills the area of the Shape marker under the cursor with the selected pattern,
  then places a closed wall along its outline using the current Wall Tool settings.
  Pattern fill is undoable via Ctrl+Z; wall placement is not undoable (pending
  a Dungeondraft API solution for wall node deletion).

### Removed
- Wall undo/redo (`WallBuildRecord`, `RoomBuildRecord`) — removed until a reliable
  deletion API is available. `WallBuilder` no longer records history.

---

## [1.0.3] — 2026-02-24

### Added
- **Undo/redo support for Pattern Fill.** Placing a pattern shape is now fully
  undoable and redoable via the standard Dungeondraft Ctrl+Z / Ctrl+Y shortcuts.
  `PatternFillRecord` snapshots the created shapes with `PatternShape.Save()` at
  placement time; `undo()` removes the live nodes, `redo()` restores them via
  `PatternShapes.LoadShape()`.
- **Undo/redo support for Wall Builder.** Placing a wall is now fully undoable and
  redoable. `WallBuildRecord` snapshots the wall with `Wall.Save()` at placement
  time; `undo()` removes the live node, `redo()` restores it via `Walls.LoadWall()`.

### Changed
- History record classes (`PatternFillRecord`, `WallBuildRecord`, `MirrorPlacementRecord`)
  are now centralised in `scripts/tool/BuildingPlannerHistory.gd`.
  Feature files reference them via a `preload` constant.

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
