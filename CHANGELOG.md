# Changelog

All notable changes to BuildingPlanner will be documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.1.5] — 2026-03-01

### Added
- **Room Builder — scroll wheel controls.**
  While Room Builder mode is active, the scroll wheel now adjusts the shape being placed
  without leaving the tool:
  - **Scroll up / down** — rotates the placement shape by ±5 ° per tick
    (`shape_angle_offset`, additive over the GuidesLines base angle).
  - **Alt + Scroll up / down** — scales the placement shape by ±10 % per tick
    (`shape_scale_factor`, multiplicative over the GuidesLines base radius; minimum 10 %).
  Both adjustments are reflected live in the shape preview.

### Fixed
- **Clicks on Dungeondraft windows / popups now work correctly.**
  The input overlay previously intercepted `_input` before Godot's GUI layer could
  consume it, causing clicks on open dialogs (preferences, warnings, custom mod windows)
  to be silently swallowed. The overlay now checks `Global.Editor.Windows` and skips
  processing if any registered window is visible.
- **Ctrl+scroll (camera zoom) no longer triggers Room Builder scroll handlers.**
  Added an early-exit guard when `event.control` is held, consistent with the
  GuidesLines MarkerOverlay pattern.
- **Input handling order restructured** to mirror GuidesLines `MarkerOverlay`:
  scroll-wheel events are processed before left-click boundary guards, so wheel
  input is never accidentally filtered out by the canvas-area checks.
- **Top and bottom screen margins (100 px each) added** to the left-click guard.
  Clicks in the top UI bar area and the bottom status bar area no longer reach
  the world canvas handler.

---

## [1.1.4] — 2026-02-28

### Added
- **Roof Builder** — new mode that places a Dungeondraft roof along the outline of a
  Shape or Path marker.
  - **Texture** — scrollable grid of all installed roof textures (sourced from RoofTool).
  - **Width** — eave width in Dungeondraft units (5–500, default 50).
  - **Type** — Gable / Hip / Dormer roof geometry.
  - **Layer** — Over / Under render-order sorting.
  - **Placement mode** — three sub-modes controlling where the roof width is projected:
    - *Ridge along area* — uses the marker outline as the ridge line.
    - *Expand* — eave sits at the marker outline, roof extends **outward**.
    - *Inset* — eave sits at the marker outline, roof extends **inward**.
  - **Shade** — optional sunlight shading toggle with configurable sun direction (0–360 °)
    and contrast (0.0–1.0).
  - Full **undo / redo** support via the History API (`RoofBuilderRecord`).

### Technical
- `RoofBuilder.gd`: new feature class. `build_at(coords)` resolves the fill polygon via
  `GuidesLinesApi.compute_fill_polygon`, builds the footprint with `_build_roof_polygon`
  (applies `Geometry.offset_polygon_2d` for Expand/Inset modes), then calls
  `Roofs.CreateRoof` → `World.AssignNodeID` → `Roof.Set/SetTileTexture/SetSunlight`.
  The polygon is passed with a two-point overlap (`[…D, A, B]`) to cover the seam left
  open by Dungeondraft's native roof renderer.
- `BuildingPlannerHistory`: new `RoofBuilderRecord` class (undo frees the roof node,
  redo restores it via `Roofs.LoadRoof`).
- `BuildingPlannerTool`: `Mode.ROOF_BUILDER` added to the `Mode` enum; `_roof_builder`
  loaded and dispatched from `handle_roof_builder_click`.
- `BuildingPlannerToolUI`: new `RoofPanel` inner class; `MODE_ROOF_BUILDER = 5`;
  full sidebar section with all controls and callbacks wired.
- `BuildingPlannerOverlay`: `Mode.ROOF_BUILDER` branch added to the input dispatcher.

---

## [1.1.3] — 2026-02-28

### Added
- **Path color picker integration with ColourAndModifyThings.**
  The **Color** picker in PathPanel (Path Builder and Room Builder → Outline: Path) now
  actually applies to created paths.
  - When **ColourAndModifyThings** is installed: color is applied immediately via
    `modulate` and is also written into `ModMapData["UchideshiNodeData"]`, so it
    **persists across map save/reload** through CAMT's own rendering pipeline.
  - When **ColourAndModifyThings** is not installed: the color picker is **disabled**
    (grayed out with an explanatory tooltip), preventing user confusion about
    non-persistent changes.

### Fixed
- `PathBuilder.build_at()` and `RoomBuilder._build_path()` previously lost the
  selected color after the mandatory `Save()` + `LoadPathway()` re-registration
  cycle (Dungeondraft resets `modulate` to white on load). Color is now re-applied
  to the loaded node.

### Technical
- `BuildingPlannerUtils`: new static helper `store_path_color_for_camt(global_ref, node_id, color)`.
  Writes a minimal CAMT-compatible data entry into `ModMapData["UchideshiNodeData"]`;
  merges with any existing CAMT record to preserve shader/edge-blur settings.
  No-op when CAMT is not installed.
- `PathBuilder`, `RoomBuilder`: `preload` for `BuildingPlannerUtils` added.
  Post-`LoadPathway` block re-applies `modulate` and calls `store_path_color_for_camt`.
- `BuildingPlannerToolUI` — `PathPanel`: new method `update_camt_color_state(gl)` enables
  or disables `color_picker` based on the presence of `"UchideshiNodeData"` in `ModMapData`.
  Called for both `_pb_path_panel` and `_rb_path_panel` inside `try_build_all_grid_menus()`.

---

## [1.1.2] — 2026-02-27

### Changed
- **Room Builder — Outline mode selector.**
  The sidebar for Room Builder now has an **"Outline"** `OptionButton` (Wall / Path) that
  replaces the always-visible WallPanel.
  - **Wall** (default) — same WallPanel as before (texture grid, color, shadow, joint).
  - **Path** — a full PathPanel appears: texture grid, color, width, smoothness, layer,
    sorting, and all path effects (Fade In/Out, Grow, Shrink, Block Light).
  Only the panel that matches the active selection is visible at any time.

### Technical
- `RoomBuilder`: new `enum OutlineMode { WALL, PATH }` + `active_outline_mode` field.
- `RoomBuilder`: `_build_room_single_impl` and `_build_room_merge` dispatch to `_build_wall()`
  or the new `_build_path()` based on `active_outline_mode`.
- `RoomBuilder`: `_build_path()` mirrors `PathBuilder.build_at()` but accepts a pre-computed
  polygon (skips `compute_fill_polygon` call), complete with Save/Load registration.
- `BuildingPlannerToolUI`: `_rb_path_panel` (PathPanel) created, wired (10 callbacks), and
  added to grid-menu lifecycle.  `_rb_wall_container` / `_rb_path_container` toggle visibility
  via `_on_rb_outline_mode(index)`.

---

## [1.1.1] — 2026-02-27

### Added
- **Path Builder mode** — Click anywhere inside a Shape marker to trace a **closed path** along its outline.
  Uses Dungeondraft's PathTool API to create properly registered paths with full SelectTool support
  (select, move, delete). Configurable settings include:
  - Path texture (scrollable grid sourced from PathTool)
  - Color modulation (ColorPickerButton)
  - Width (0.1–10.0 scale factor)
  - Smoothness (0.0–1.0 slider)
  - Layer (0–9)
  - Sorting (Over / Under)
  - Effects: Fade In, Fade Out, Grow (taper start), Shrink (taper end), Block Light
- **PathBuilderRecord** undo/redo support in BuildingPlannerHistory — paths can be undone/redone via Ctrl+Z.

### Technical
- Paths are registered via Save/Load cycle to ensure proper Editor integration (node_id metadata + deletion registry).
- Closed paths are created by appending the first polygon point to the end (Line2D standard technique).

---

## [1.1.0] — 2026-02-26

### Added
- **Custom tool icon** (`icons/BuildingPlanner_Icon_no_outline_32x32.png`) now displayed in the Dungeondraft toolbar.

### Fixed
- **Merge mode no longer crashes when placing a room on top of an identical existing one.**
  `_build_room_merge` and `_build_room_single_impl` now call `_sanitize_polygon()` before
  passing the polygon to `DrawPolygon` / `AddWall`. The sanitizer strips consecutive
  duplicate / zero-length edges produced by `place_shape_merge` when two congruent shapes
  are merged, preventing the *"Please create a shape that does not intersect upon itself"* error.

---

## [1.0.10] — 2026-02-25

### Added
- **Pattern and wall icons in the selection grid are now tinted with their default color.**
  Uses `GetDefaultColor(texture)` / `GetWallColor(texture)` to apply `set_item_icon_modulate`
  on each icon when the grid is built.

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
