# Native Smart Tile floor and Room Builder

## Decision

Use **Floor Fill** as the UI entry with Pattern / Smart Tiles selection. Retain
the internal PATTERN_FILL value and PatternFill script so current room templates,
pattern history and saved material settings keep their existing contract.
Floor Fill and Room Builder have independent Pattern / Smart Tiles panels.
Smart Tiles provides color, sampling and native material thumbnails; standalone
fill additionally supports erasing native floor. Room mode offers No fill.
No manifest version, dependency pin or release workflow changes are needed.

## Host evidence

All paths below are relative to workspace `Dungeondraft_extracted/`:

- `scripts/tools/layout/FloorShapeTool.cs`: polygon mode is already supported;
  SmartTileId and WallTexture proxy the static native floor brush settings.
- `scripts/world/FloorShapes.cs`: Save contains level-wide polygons and automatic
  wall IDs. AddPolygon delegates to native clipping and finalization. DrawPolygon
  additionally captures native history and updates tiles. FinalizeOutlines can
  rebuild automatic walls and clip cave walls; this is not an object factory.
- `scripts/world/Shapes.cs`: ClipPolygons unions input with existing Paths using
  Clipper NonZero fill and rebuilds the shared outlines. It calls the virtual
  FinalizeOutlines method, including FloorShapes' wall/cave processing.
- `scripts/world/FloorTileMap.cs`: UpdateRect paints every cell in floor/ceil
  bounding-box coverage that overlaps any shared outline, assigns the selected
  tile's native tint and calls UpdateBitmaskArea. Existing floor inside that box
  can therefore be repainted even outside the newly submitted polygon.
- The same file's GetRect uses WorldToMap for the end, whereas UpdateRect uses
  ceil. Native DrawPolygon history can omit a partial last row/column for bounds
  off the tile grid. This prototype captures the ceil coverage explicitly.
- `ChangeFloorShape.cs`: native undo replays automatic WallRecords across two
  frames, restores cell data and shared outlines. Wall/portal restoration cannot
  be replaced with simply reloading one FloorShape node.
- `scripts/world/Level.cs`, `scripts/world/FloorTileCamera.cs`,
  `shaders/Floor.shader`: floor contours and the rendered tilemap are separate
  parts of native floor rendering and native map serialization. Cell coverage
  alone does not establish the visible precision of arbitrary contour edges.

## Implemented boundary

SmartTileFill resolves the same public GuidesLines polygon as PatternFill,
validates map bounds, loaded tile texture, host readiness and HistoryApi, then
calls DrawPolygon with SuppressHistory temporarily enabled, without creating a
second native history record. This leaves Rect2/TileRect overload selection inside
C#: dispatching the overloaded UpdateRect directly from GDScript is avoided.
Cell colors use the engine's get_cell_color/set_cell_color GDScript API, rather
than the PascalCase names used by C# callers. Preflight checks these methods.
Native brush tile/wall selection is restored immediately. The no-wall icon stops
new automatic walls; levels already containing automatic walls are rejected
before mutation. Manual walls remain independent.

History retains before/after shared contours plus affected cell IDs and colors,
regenerates bitmasks on replay, and guards the original world and level lifetime.
Room history uses sparse owned coordinates instead of capturing empty gaps
between rooms. Standalone history keeps native rectangular edit coverage.
The tile selector uses loaded TileSet textures and resolves IDs again at placement;
numeric asset IDs are not persisted. Native floor serialization handles placed
content. There is no separate mod floor node or runtime dependency.

The mode uses the native Floor layer. Selected tint is written per cell after
native placement, without changing shared TileSet modulation. Sampling reads
the loaded tile texture and native cell tint. Rotation, arbitrary pattern layers
and pattern outline controls do not apply to this backend. Bevels and skirting are not promised. Native C#
interop, clipping, autotile output and save/load still need host validation.

Hover uses a separate hidden engine TileMap for autotile selection, then clips
each cell's atlas-textured polygons to the GuidesLines region. The native TileSet
is shared read-only; map cells, floor contours and brush state stay unchanged.
Tile IDs/source geometry are cached with change invalidation; clipped cell nodes
are retained and reused. Color-only updates skip clipping and autotiling.
Preview work is capped at 4096 bounding-box cells. Existing adjacent cell IDs are
included for border connections; repainting other pre-existing shared contours
outside the marker polygon is not visualized. Native double tiles, material UVs,
bridged holes and contacts still require visual comparison in Dungeondraft.

## Room floor ownership and history

RoomFloorState retains per-level native baseline contours, lazily captured
baseline cells, and per-room polygon/material contributions. Single/group members
use independent session IDs; persistent rooms use their marker IDs. Boolean
rebuilds update contributions before committing shared floor. Affected existing
rooms retain their saved fill kind/material; Merge takes the active style.

Every affected level/material is preflighted before native floor mutation. Commit
restores baseline contours/cells, unions surviving contributions through native
AddPolygon with automatic walls disabled, paints cells intersecting each owned
polygon and updates native bitmasks. Existing baseline floor and mixed materials
reappear when the last covering room is removed. Contributions paint in saved
order; later contributions win where their cells overlap.

FloorTileMap.UpdateRect reads the globally active World.Level. Room commits paint
the target level directly, with half-pixel inset cell intersection checks, so
multi-level rebuilds do not need to switch the UI's active level. Native clipping
still comes from FloorShapes; there is no per-room floor node.

RoomBuilderRecord owns the before/after shared floor records and ownership state
alongside marker and Wall/Path history. Failure rolls back the entire transaction.
Undo/redo, tool switching, map generation guards and record eviction retain the
existing compound history contract. Room templates add optional fill_mode and
tile_style fields; old files default to Pattern, and missing tile assets are
resolved/rejected before changing any controls.

Ownership lasts for a map session, matching MarkerObjectRegistry. External edits
to native contours disjoint from owned rooms are incorporated into the baseline;
changed unowned cells (including gaps inside the captured bounding rectangle)
are incorporated too. Thus standalone/native floor edits away from rooms survive
subsequent room rebuilds and undo/redo. Changed contours shared with owned rooms,
or changed cells intersecting an owned room, cancel the conflicting action.
Reopen the map to start new ownership over its current native floor. This avoids
guessing how an overlapping external edit should be attributed to rooms.
Large-session recomposition scans all owned
room cells/contours on an affected level; regional deltas are the upgrade path.
Automatic wall/portal replay remains necessary before lifting that restriction.

## Validation

The reported full application exit was confirmed in Windows Application event
1000 on 2026-11-17: Dungeondraft 1.2.0.1, exception 0xc0000005, executable offset
0x13e07ca. The crash recurred at the same offset after the cell-color and overload
changes. Inspection of the second minidump's exception context and executable
instructions identified a built-in Variant method dispatch on a NIL receiver,
with two arguments, rather than establishing a failure in native DrawPolygon.

The fill's Global.Theme.get_icon("NullMin", "Icons") matches that failure:
scripts/framework/modding/ModScript.cs does not inject Theme into a mod's Global.
The first test fixture incorrectly supplied it. The icon now comes from the
FloorShapeTool wall menu's inherited Control theme, verified before any mutation.
Tests deliberately omit Global.Theme and reject a missing control/icon safely.
The dispatch behavior is consistent with the release-mode method lookup in
[Godot 3.4 variant_call.cpp](https://github.com/godotengine/godot/blob/3.4/core/variant_call.cpp).
The user confirmed that standalone Smart Tiles placement and preview work after
the missing-theme fix. The new room/settings integration still needs host checks.

Optional crash tracing (_trace_enabled = true; disabled by default) writes and
closes a checkpoint file after each major stage:
user://buildingplanner-smart-tiles.log (on this Windows installation,
C:/Users/Smyrn/AppData/Roaming/Dungeondraft/buildingplanner-smart-tiles.log).
The next fill replaces the previous attempt's trace. It records polygon/floor
and cell snapshot entry, entry/return of DrawPolygon and completion, without
depending on console output or changing the host's logging preference.

A standalone viewport readback additionally checks
that selected autotiles render inside the contour and stay transparent outside.

Standalone Godot tests exercise call arguments, brush restoration, tile selection,
backend switching, partial boundary cells, colors, undo/redo, map guards and
preflight rejection. They substitute host classes and cannot prove host behavior.

Additional integration tests run the authored GuidesLines public API and cover
all five room modes, mixed Pattern/tile merges, underlying-floor restoration,
two levels, failed-outline rollback, external-edit preservation, Path/group input,
bridged hole coverage, tile thumbnails, tint/erase/sample behavior and JSON room
template roundtrips including legacy defaults and missing assets.

Pending Dungeondraft checks on a scratch map with _Lib and GuidesLines enabled:

- Grid-aligned rectangle, off-grid rectangle, rotated polygon, concave contour,
  circle, thin sliver and bridged hole/island: compare visible edge and cell mask.
- At least two native/custom Smart Tile sets: corners, edges, contacts, mixed
  neighbors and existing floor elsewhere inside the edited bounding rectangle.
- Undo/redo repeated and interleaved with native building edits; verify edge cells,
  colors, original contours and absence of extra history entries.
- Existing automatic walls: placement must be rejected without edits. Existing
  manual walls and cave boundaries: verify no lost walls, portals or cave content.
- Save/reopen, level switches, map switches, tool switches and unload; verify
  native persistence, original level replay and restored native brush selection.
- Missing/late API, absent tile assets, busy host and out-of-map contours: no edits.
- Large contours/maps: assess snapshot memory and latency before room-wide replay.
- Room Builder: all five modes with Wall and Path, different tile colors/materials,
  groups, two levels, repeated undo/redo, tool switches and save/reopen templates.
- Standalone color/erase and both sample pickers: verify native tint persistence
  and that shared native brush/tileset defaults stay unchanged.

See [the performance audit](AUDIT_SMART_TILES_2026_11_18.md) for the idle-frame,
allocation, history-memory and dependency-side redraw findings and checks.
