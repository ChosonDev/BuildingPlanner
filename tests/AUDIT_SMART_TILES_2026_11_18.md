# Smart Tiles / Room Builder performance audit, 2026-11-18

Scope: the current uncommitted native tile panels, placement, preview, room floor
ownership and history changes. Existing user changes and the untracked
RoofBuilder directory were preserved. No dependency or manifest version changes.

## Findings and fixes

| Severity | Finding | Change and evidence |
| --- | --- | --- |
| High | Room preview rebuilt cell nodes while the cursor was stationary. Newly created settings Dictionaries failed the existing identity comparison. | Compare flat settings values and cache the source geometry. A regression loop of 120 idle calls now causes one tile build, with stable cell instance IDs. Before the fix, the same scenario changed cell IDs and scanned the catalog 121 times. |
| High | SmartTileFill scanned the entire TileSet on every get_settings call. | Resolve IDs through a lazily built index keyed by texture instance ID/path. TileSet.changed invalidates it; switching TileSets disconnects the old resource. Weak references avoid retaining old TileSets/worlds. The idle loop now scans once. |
| High | Room floor history captured all cells in the bounding rectangle between rooms. | Room snapshots now store explicit owned coordinates. The distant-room fixture stores 13 cells; its old 64x64 bounding rectangle would capture 4096 cells. Standalone fills retain the full native edit rectangle because native UpdateRect can repaint it. |
| Medium | Each Smart Tiles refresh freed and recreated Polygon2D cells. | Retain a pool and reuse nodes in O(1) per node. Tint-only changes update color without rerunning clipping/autotiling. Clearing releases texture/material references. The pool and its geometry retain a high-water mark until the owning overlay is destroyed. |
| Medium | Template preview transformed/copied/sanitized the same group every frame. | Cache geometry by source ID, transform, cell size, level and public geometry revision. Tests verify one batch for 120 idle calls and new batches after rotation/motion. Old APIs without a revision token retain fresh template polling. |
| Medium | Placement repeatedly serialized the complete native floor for each room/material. | Reuse preflight snapshots within a transaction, refresh once per level before mutation, and release cached contexts after success/failure. Two placements in the fixture now call native Save six times in total, independent of the repeated per-material checks. |
| Medium | Comparing floor contributions converted entire room/style dictionaries into strings. | Compare marker membership, polygon values, texture identity and color directly. No style/texture serialization is needed for the equality check. |
| Low | Every successful standalone click performed several synchronous diagnostic file opens/writes and printed checkpoints. | Crash tracing is opt-in through _trace_enabled (default false). Errors/warnings still use Logger. A test verifies no trace file is created with diagnostics disabled. |

Packed polygon conversion, tile material/spacing lookup and cell origin lookup
were also hoisted out of inner loops where possible. No frame-time native map
Save, cell snapshot, disk write or asset load was added.

## Invalidation and correctness

The preview caches include cell size, level/source identity, material selection,
source template transform and the available public geometry revision. Color-only
updates reuse raster geometry. TileSet resource changes invalidate ID resolution
and the preview; HistoryApi recorded/undo_end/redo_end signals invalidate native
neighbor connections without rescanning the catalog unnecessarily. Old signal
sources are disconnected when replaced. The existing map/tool lifecycle still
clears/destroys owned overlays.

Sparse snapshots retain cell IDs/colors and still update neighboring bitmasks on
replay. Existing tests cover boolean modes, mixed fill kinds, native baseline
restoration, external edits, multilevel undo, template JSON, source readiness and
rollback. The new tests extend those checks with operation counts and instance
identity; a stable image alone would not prove the absence of redundant work.

## Remaining costs and limits

- GuidesLines' public set_shape_preview/set_template_preview requests expire on
  the next idle frame. BuildingPlanner must renew them every frame. The current
  GuidesLines MarkerOverlay marks API previews for redraw while present, and
  set_template_preview also regenerates its own group. This dependency-side work
  remains; skipping renewal would make the source preview disappear. Eliminating
  it requires a retained-preview/heartbeat change in the GuidesLines public API
  and overlay, outside the BuildingPlanner changes audited here.
- Polling creates small state Dictionaries/Arrays. Expensive room geometry, cell
  clipping, node creation and catalog scans are no longer idle-frame operations.
  No claim of zero allocations or zero GPU draws is made.
- Moving a tile preview still clips actual changed geometry, with work bounded
  to 4096 bounding-box cells per renderer. Dense contours/groups can be costly;
  a viewport/mask renderer is the documented upgrade path.
- Room placement still recomposes all owned contributions on an affected level.
  Ownership/history retain native contours and copies of owned-cell metadata.
  These are click/history costs rather than per-frame costs; regional deltas are
  the next optimization if large-map profiling justifies them.
- _Lib history notification delivery and native rendering remain host behavior.
  Standalone Godot verifies logic/render output and operation counts, not actual
  Dungeondraft FPS, native GPU allocation, or every C# callback interaction.

## Runnable verification

Final checks: 198 tests / 3585 assertions passed in run
1629c0eb57df4f0794704b77fbd32b79; 10 runtime smoke scenarios passed in
runtime-check-1f4675bc39d740f6bd17f0842c0835d4; git diff --check passed.
These reports live in the ignored tests/results directory.

From the workspace root:

```powershell
python Mods/BuildingPlanner/tests/run.py
python Mods/BuildingPlanner/tests/run.py --test test_smart_tile
python Mods/BuildingPlanner/tests/check_runtime.py
git -C Mods/BuildingPlanner diff --check
```

Native follow-up: compare stationary and moving previews on a scratch map,
including a large group, color changes, native undo/redo under the stationary
cursor, level/tool switches, returning to the canvas and a changed tile palette.
Use the host profiler for frame time/GPU/memory conclusions.
