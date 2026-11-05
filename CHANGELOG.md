# Changelog

All notable changes to BuildingPlanner will be documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.2.4]

### Changed
- Share standalone native-object history while preserving path tint, world IDs,
  original order and shared roof sunlight replay.
- Rebuild room cuts using explicit saved settings without temporary feature objects
  or runtime property introspection; retain isolated history snapshots.
- Poll the compact GuidesLines shape state when available, with full-state fallback,
  and access UI lifecycle through methods instead of private controls/panels.

### Added
- Test runner accepts `--keep-results N` to retain the newest completed reports
  while preserving running and unrecognized artifacts; report retention is checked
  in a disposable directory.
- Wall Builder and Path Builder trace nearby open or closed GuidesLines Path
  markers, with validated serialized coordinates and undo/redo. Shape regions
  remain the fallback when the nearest marker within 100 world units is not a Path.

### Fixed
- Pass `false` explicitly to native PatternShape, Pathway and Roof `Save(bool)`
  calls during history capture, preserving world IDs without relying on C#
  optional arguments across the GDScript boundary. Keep Wall's argument-free Save.
- Log room history snapshot and registration stages to locate native failures
  after temporary Single marker deletion.
- Reject incomplete room shape state and missing saved room metadata with diagnostics
  and rollback; preserve layer selections when LayerApi returns no layers.
- Distinguish ordinary marker misses from malformed API geometry, and report missing
  standalone fill textures while retaining Room Builder's No fill option.
- Use arrays for asset paths and avoid eagerly allocated registry lookup defaults.
- Invalid Path/Room API results, capture failures and asset-loading failures now
  produce diagnostics; empty layer refresh preserves the previous selection.
- Path creation avoids copying its input, roof polling avoids unchanged lighting
  allocations, and roof offset sanitization avoids a redundant Array conversion.
- Roof initialization applies texture and shared lighting before geometry, matching
  native Hip roof loading and avoiding different edge widths after Undo/Redo.
- Roof controls refresh after native sunlight edits and history on the same level,
  while preserving draft edits until the native lighting changes.
- Successful Single rooms omit temporary marker records from compound history.
- Room clicks use their supplied coordinates for snapping; wheel rotation uses
  the consistent 0–360 degree range.
- Room Builder uses the saved Shape parameters regardless of the active GuidesLines
  marker tab. Merge includes the clicked level as well as existing room levels.
- Path color controls track late CAMT initialization without reopening the panel.
- Late GuidesLines registration preserves edited panel settings and Room sub-mode
  and outline selections. Enable safely handles APIs without tool-state access.
- Roof controls read each level's shared lighting on level changes, including
  before placement; new maps initialize style defaults using their tile size.
- Plain-marker cuts retain marker history without empty native-object snapshots;
  Difference without overlap still creates no Undo step.
- Room wheel controls leave sidebar scrolling available. Single rooms use their
  own marker outline even when other shapes overlap the placement, independently
  of the active GuidesLines Conform/Wrap mode (requires its companion API update).
- Conform and Difference preserve each existing room's materials, outline type,
  color and settings; cuts in plain GuidesLines markers create no native objects.
- Map catalog restoration loads only the selected texture; a missing asset falls
  back to the first entry and its default color. Failed loads clear stale textures.
- Path deletion and undo remove owned CAMT persistence keys; repeated redo does
  not accumulate old IDs. Failed toolbar creation disconnects and retries cleanly.
- Map transitions clear stale textures and restore selected assets and user colors
  from the new catalog; roof choices persist across tool switches.
- Roof placement requires a selected texture, split offsets retain the largest
  contour by area, and Pattern Fill redo restores sibling order.
- Room previews validate the same API capabilities and shape settings as placement;
  history restores native fill/wall colors without applying a second tint.
- Hiding sections and disabling the tool release owned asset-search focus.
- Layer selectors publish their fallback to feature settings after map/layer changes.
- Discarded fill/path/roof history releases saved data in both directions; redo
  loaders receive isolated snapshots for repeatable undo/redo.
- Boolean rooms retain geometry on each original level, including merged rooms
  spanning levels; history restores fills and outlines to their owning levels.
- Room preview and placement refresh GuidesLines state through its public API.
- Standalone walls record one undoable action and use native Manual wall semantics.
- Roof defaults convert tile width to pixels per map and retain user choices
  across tool switches. Sunlight uses the host's persistent level settings; undo
  and redo restore lighting and roof order together.
- Colorable patterns retain their thumbnail's default tint; Room Builder exposes
  No fill. Pattern loading keeps native repeat flags without a second SetOptions.
- Asset selection uses GetAssetTexture without changing native tools or Infobar.
  Path catalogs remain complete and stable regardless of native search filters.
- Room operations group marker edits, pattern fills and Wall/Path outlines into
  one history action, restore replaced objects and registry associations, and
  roll back failed creation. Pattern creation avoids native duplicate history.
- Wall and path textures remain independent between standalone and room modes.
- Geometry validation rejects malformed, non-finite, degenerate and crossing
  outlines while preserving GuidesLines hole bridges and tangent contours.
- Path initialization uses world-assigned IDs; redo restores color and tree order.
- Tool/map lifecycle cleans up overlays and owned subscriptions safely.

### Changed
- Paths load directly from native saved data without creating a temporary node;
  native initialization, tint, history and Under/Over ordering are retained.
- Layer selectors resolve their own panel settings. Release archives omit the
  three unused icon variants while retaining the toolbar icon.
- Room Builder displays wheel rotation/scale overrides and offers a reset button.
- Asset search caches normalized names, splits words once and restores selection
  during filtering. White paths avoid new CAMT entries; final loaded paths own tint.
- Registry cleanup no longer returns queued nodes. Unused camera and mode state
  are removed, panel traversal is shared, and release archives exclude TODO.md.
- Polygon checks skip non-adjacent-edge work for triangles and reject distant
  vertices before closest-point calculations, retaining contact tolerance.
- Room API capabilities are checked on construction, and preview/placement share
  one validated shape-parameter calculation. History rejects stale maps first.
- Layer/sorting controls, default tints, polygon area and scene removal use shared
  helpers. Roof styles use the same grid as other panels; Snappy binding is cached.
- Layer selectors share one query and sorted snapshot; Room preview skips public
  API state allocation over UI. Geometry validation avoids temporary endpoint
  arrays and repeated Ridge sanitization. Room rebuilding copies only level data.
- Panel controls and bound signals share small helpers; standalone features use
  one build entry point and shared level validation. Fresh path loads avoid a
  redundant copy while history retains isolated replay snapshots.
- Panels bind directly to feature settings; Room Builder retains independent fill,
  wall and path components instead of copying settings into temporary builders.
- Asset catalogs are shared lazily per map while panel searches and selections
  remain independent. Map changes and unload invalidate the catalogs.
- Panel helpers, canvas dispatch, native path restoration and history guards are
  shared. Standalone fill/path history stores one node instead of parallel arrays.
- Room preview clears only once while idle over UI; active previews still refresh
  each frame for the GuidesLines draw lifecycle.
- Polygon resolution and history routing are shared by the feature builders.
- Wall thumbnails are tinted without loading full textures; disjoint polygon
  edges skip intersection calls, wall reload lookup is constant time, and overlay
  scripts are retained across tool switches.
- Texture grids populate only for the active section and survive tool switches.
- Raw pattern textures reuse Godot's existing resource cache.
- Room construction shares the feature builders; unused Mirror Mode helpers and
  unused grid methods were removed. No new dependency was added.
- Room Builder requires the companion GuidesLines history-capture API changes.

---

## [1.2.3] — 2026-05-11

### Fixed
- **Pattern Fill: Colorable textures from custom packs are now supported.**
  `PatternPanel` now correctly preserves the texture's resource path, allowing Dungeondraft's native C# backend to recognize colorable textures loaded via Godot's `Image.load()` fallback and apply the correct shader.

---

## [1.2.2] — 2026-05-01

### Fixed
- **Pattern Fill: custom pack textures no longer produce untextured shapes.**
  `PatternPanel` now filters out patterns whose texture is not registered in
  Godot's `ResourceLoader` (i.e. textures from custom asset packs without
  `.import` files). Only patterns that can be reliably loaded and applied via
  `SetOptions()` are shown in the panel.

---

## [1.2.1] — 2026-05-01

### Added
- **Search field in texture grids.** All four texture selection grids (Pattern Fill,
  Wall Builder, Path Builder, Roof Builder) now have a search/filter field above the
  grid. Typing filters items in real time; a clear (×) button resets the filter.
  Keyboard shortcuts are suppressed while the field has focus so letters reach the
  search box instead of Dungeondraft's tool shortcuts.

### Technical
- New `SearchableGrid` inner class in `BuildingPlannerToolUI.gd` encapsulates a
  `LineEdit` + clear `Button` + `ItemList` inside a `ScrollContainer`. Filtering
  uses word-by-word substring matching (identical to AdditionalSearchOptions).
  `on_item_selected` callback receives the original DD index, so `OnItemSelected`
  calls on source GridMenus remain correct after filtering.
- `PatternPanel`, `WallPanel`, `PathPanel`, `RoofPanel` refactored to use
  `SearchableGrid` instead of building the `ItemList` manually.

---

## [1.2.0] — 2026-05-01

### Added
- **Mod Versions menu tracking** — BuildingPlanner now registers with `UpdateChecker`
  (`CreepyCre._Lib`). The mod appears in the *Mods → Mod Versions* window with its
  current version and, when online, shows the latest release from GitHub alongside a
  download button if an update is available.

---

## [1.1.9] — 2026-05-01

### Changed
- **Release packaging** — the ZIP archive now contains a `BuildingPlanner/` subfolder
  instead of placing files at the archive root.  
  Files `.gitignore` and `.gitmodules` are excluded from the release.

---

## [1.1.8] — 2026-05-01

### Added
- **Layer selection for Pattern Fill and Path Builder.**  
  The layer controls in the *Pattern Fill* and *Path Builder* panels (and the corresponding
  sub-panels inside *Room Builder*) have been replaced with dynamic **OptionButton** dropdowns.  
  Items are populated from `LayerApi.get_user_layers()` and show the z-index together with
  the human-readable layer name (e.g. `100: User Layer 1`).  
  The dropdown refreshes automatically whenever the active mode changes, on tool activation,
  and whenever `ModSignalingApi.layers_changed` fires (i.e. when ManageLayers adds, renames,
  or removes a layer).  
  A fallback entry `100: User Layer 1` is shown when `LayerApi` is unavailable.

---

## [1.1.7] — 2026-03-01

### Added
- **Room Builder — Wrapping sub-mode** *(requires GuidesLines v2.2.5+)*  
  New sub-mode available in the *Sub-mode* dropdown of Room Builder.  
  The new shape is placed on the map but its own outline is **dented** wherever it overlaps
  existing Shape markers (`GuidesLinesApi.place_shape_wrapping` — Difference applied to the
  new shape only; existing markers are left completely unchanged).  
  Pattern fill and outline are built for the trimmed polygon. If the new shape is fully
  consumed by existing markers, placement is aborted gracefully and no marker is left.

- **Room Builder — Difference sub-mode** *(requires GuidesLines v2.2.5+)*  
  New sub-mode available in the *Sub-mode* dropdown of Room Builder.  
  A virtual cutter shape is applied at the click position without placing any new marker
  (`GuidesLinesApi.apply_shape_difference`). Every existing Shape marker that overlaps
  the cursor position has the overlapping area **punched out** of it. Pattern fill and
  outline for each affected marker are rebuilt from the new clipped polygon.  
  Acts as a no-op when no existing markers are found at the click position.

---

## [1.1.6] — 2026-03-01

### Added
- **Room Builder — Conforming sub-mode** *(requires GuidesLines v2.2.5+)*  
  New sub-mode available in the *Sub-mode* dropdown of Room Builder.
  When a room is placed, the new shape is kept intact while every existing Shape marker
  that overlaps it is **dented** to accommodate it
  (`GuidesLinesApi.place_shape_conforming` — Difference applied to existing markers only).
  Pattern fill and outline are rebuilt for both the new marker and every dented marker.
  Falls back gracefully to Single-like behaviour when there are no overlapping markers.

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
