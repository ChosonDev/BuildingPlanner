# Building Planner

**Version:** 1.3.0
**Author:** Choson  
**Depends on:** [CreepyCre._Lib](https://github.com/CreepyCre/_Lib) · [GuidesLines](https://github.com/ChosonDev/GuidesLines) (v2.4.5+)

---

Generate Dungeondraft map content directly from [GuidesLines](https://github.com/ChosonDev/GuidesLines) markers.
Select the **Building Planner** tool in the *Design* category of the Dungeondraft toolbar,
then choose a mode from the sidebar.

## Features

### Hover Build Preview
Pattern Fill previews the actual boolean region under the pointer. Wall and Path
Builder preview the resolved centerline, including offset and reverse direction;
Path smoothing follows the native host algorithm. Open starts are green, ends
are orange, and an arrow marks traversal. A differing source outline is dashed blue.
Missing textures or invalid geometry show a cursor message without per-frame logs.

The preview now draws the selected textures at 60% opacity. Pattern Fill uses the
host's pattern/colorable materials, rotation, world-space tiling and optional
border. Wall Builder shows texture thickness, joint style, end textures and the
selected shadow. Path Builder shows texture width, smoothing, fade and taper.
Only ordinary UI Polygon2D/Line2D/Sprite nodes are retained under the overlay;
shared asset textures, host materials and native map objects are never modified.

Hover creates no map objects, IDs or history. Moving target queries run at most
15 times per second. GuidesLines returns a zone hash and caches visited boolean
components, including map save/load and source dependencies. An unchanged hash
does not resend polygons or rebuild preview nodes/materials. A separate parameter
hash tracks texture/color/style changes; offset/direction/smoothing preparation is
also reused when only appearance changes. Marker revisions trigger a cheap target
check; distant edits preserve the current preview. Clicks resolve fresh geometry
and settings again.
Dialogs, panels, map/tool changes and unload clear the preview. Room Builder draws
floor and Wall/Path textures alongside its marker preview; Roof preview remains a separate stage. Preview
textures are drawn above the map so they remain visible; final layer occlusion
and lighting are assessed after placement.
Camera changes redraw screen-sized annotations, while retained texture geometry
is transformed by Godot. Offscreen source edges are culled. At most 2048 source
dash commands are retained per redraw; dense source outlines use solid blue so
large nested circles do not generate tens of thousands of tiny draw commands.
The target polygon/outline itself is never simplified by this limit.

This feature requires GuidesLines 2.4.6 or later with
`get_build_preview_target()` and geometry revisions. Update both mods together.
Older installed APIs retain click-to-build and show an update message for hover.
User testing confirmed the textured previews and cache/render optimizations
working in Dungeondraft.

### Pattern Fill
Click anywhere inside a Shape marker to fill its interior with the selected terrain pattern.

Configurable settings in the sidebar:

| Setting | Details |
|---------|---------|
| Pattern | Scrollable grid of all installed terrain textures |
| Color | ColorPicker — overrides the texture's default tint |
| Rotation | 0–360 ° in 1 ° steps |
| Layer | Current map's user layers from LayerApi (default: 100, User Layer 1) |
| Outline | Toggles a border around the filled polygon |

---

### Wall Builder
Click anywhere inside a Shape marker to trace a **closed wall** along its outline.
Click near a Path marker to trace its polyline instead: open markers create open
walls and closed markers create loops. The nearest marker geometry is checked
within 100 world units; if it is not a Path, the Shape workflow applies.

Configurable settings in the sidebar:

| Setting | Details |
|---------|---------|
| Wall style | Scrollable grid of all installed wall textures (sourced from WallTool) |
| Color | ColorPicker — pre-filled with the style's default color |
| Shadow | Toggle wall shadow |
| Bevel corners | Toggle between Sharp and Bevel joints |
| Offset (px) | Wall centerline offset: 0 by default, positive outward, negative inward (-8192 to 8192 pixels) |
| Reverse direction | Off by default; reverse traversal after offset to swap asymmetric texture sides |

Offset applies to closed Shape and Path outlines in Wall Builder, Path Builder
and both Room Builder outline modes. Room floors and GuidesLines markers keep
their original footprint; wall texture thickness and path width stay unchanged.
Settings affect newly built outlines.
Existing rooms retain their saved offset when boolean operations rebuild them.
Open Paths/Lines require 0. A nonzero offset that collapses the contour or produces
multiple contours (including holes) cancels placement with a log message; room
placement rolls back as one operation. The room cursor preview shows the source
footprint together with the textured offset outline.

Reverse direction works with open and closed Path markers, Shape contours and
both Room Builder outlines. It reverses a copy after offset: open paths run from
end to start; closed contours keep their starting vertex to preserve the texture
seam. Source markers and room floors stay unchanged. Room style snapshots retain
the flag through boolean rebuilds and undo/redo. Path fade and taper options
follow the new traversal direction.

---

### Path Builder
Click anywhere inside a Shape marker to trace a **closed path** along its outline.
Nearby Path markers use the same 100-world-unit nearest-marker check as Wall
Builder. Open markers retain their endpoints. Closed markers and markers with
coincident endpoints use native Loop, smoothing the closing join without a duplicate vertex.
Crossing and collinear polylines are supported. Older GuidesLines APIs without
the geometry query retain the Shape workflow.

Configurable settings in the sidebar:

| Setting | Details |
|---------|---------|
| Path texture | Scrollable grid of all installed path textures (sourced from PathTool) |
| Color | ColorPicker — modulates the path texture tint *(requires ColourAndModifyThings; disabled otherwise)* |
| Width | Path width scale (0.1–10.0) |
| Offset (px) | Centerline offset: 0 by default, positive outward, negative inward (-8192 to 8192 pixels); closed outlines only |
| Reverse direction | Off by default; reverse traversal after offset, keeping the start vertex on closed outlines |
| Smoothness | Bezier smoothing intensity (0.0–1.0 slider) |
| Layer | Current map's user layers from LayerApi (default: 100, User Layer 1) |
| Sorting | Over / Under (render order) |
| Fade In | Fade effect at path start |
| Fade Out | Fade effect at path end |
| Grow | Taper effect at path start |
| Shrink | Taper effect at path end |
| Block Light | Toggle light occlusion |

> **Path placement is fully undoable** via Ctrl+Z / **History API**. Paths are properly registered
> with Dungeondraft's Editor and can be selected, moved, and deleted via SelectTool.

---

### Roof Builder
Click anywhere inside a Shape marker region to place a **roof** along its resolved outline.

Configurable settings in the sidebar:

| Setting | Details |
|---------|--------|
| Roof texture | Scrollable grid of all installed roof textures (sourced from RoofTool) |
| Width | Eave width in pixels; initially copied from RoofTool's tile width using the map's tile size |
| Type | Gable / Hip / Dormer |
| Layer | Over / Under (render-order sorting) |
| Placement mode | *Ridge along area* — outline is the ridge line; *Expand* — eave at outline, roof grows outward; *Inset* — eave at outline, roof grows inward |
| Shade | Sunlight shading for all roofs on the current level; Sun Direction (0–360 °) and Contrast (0.0–1.0), applied when placing a roof |

Lighting controls read the destination level when switching levels or maps.
Roof style defaults initialize per map; tool switches preserve your choices.

> **Roof placement is fully undoable** via Ctrl+Z / **History API**, including changes to the level's shared sunlight settings.

---

### Room Builder
One-click room creation — places a pattern fill **and** a closed outline simultaneously,
using the current GuidesLines Shape parameters (radius, angle, sides), or the
selected template/group when the GuidesLines **Template** tab is active.

For templates, select the desired entry in GuidesLines and switch to BuildingPlanner
Room mode. Its exact saved geometry and current rotation/scale are used. Room's
wheel rotation and Alt+wheel scale compose with those transforms around the shared
group center, without changing GuidesLines settings. Only that center is snapped.

Group members are processed in saved order with the same Room fill and Wall/Path
settings. Shape members use the selected Single/Merge/Conforming/Wrapping/Difference
mechanic. Closed Paths receive a floor and outline; open Paths and map-clipped
Line guides receive an open outline without a floor or boolean area operation.
One click produces one compound undo/redo action. If any member cannot be built,
the whole click is rolled back. A missing/invalid template never falls back to a
different footprint. Templates require the matching updated GuidesLines API;
older APIs keep the existing Shape workflow.

Pattern settings and outline settings are configured independently in the sidebar.
Choose **No fill** in the pattern grid to create only the room outline.

Use the mouse wheel over the canvas to rotate the room, or Alt + wheel to scale it.
The sidebar displays both overrides; **Reset rotation / scale** restores 0 degrees
and 1x without changing the GuidesLines shape settings.

#### Outline mode

An **"Outline"** dropdown selects how the room border is drawn:

| Option | Description |
|--------|-------------|
| **Wall** (default) | Closed wall using WallPanel settings (texture, color, shadow, joint) |
| **Path** | Closed path using PathPanel settings (texture, color, width, smoothness, layer, sorting, effects) |

Only the panel that matches the active selection is shown in the sidebar.

#### Sub-modes

**Single** (default)  
Places a temporary Shape marker at the click position, fills it, builds a wall around it,
then removes the marker.

**Merge**

Unions the virtual shape with every overlapping existing Shape marker using
`GuidesLinesApi.place_shape_merge()`. The fill and wall for every affected polygon are
rebuilt from scratch to reflect the new merged geometry. Old fills and walls belonging to
absorbed markers are removed automatically.  
Falls back to Single (marker kept) when there are no overlapping markers.

**Conforming**

Places the new shape intact while **denting** every overlapping existing Shape marker to
accommodate it (`GuidesLinesApi.place_shape_conforming` — Difference applied to existing
markers only). The new shape's fill and outline are built normally; each dented marker's
fill and outline are rebuilt from its new clipped polygon.  
Falls back to Single (marker kept) when there are no overlapping markers.

**Wrapping**

Places a new Shape marker whose own outline is **trimmed** wherever it overlaps existing
Shape markers (`GuidesLinesApi.place_shape_wrapping` — Difference applied to the new shape
only). Existing markers are left completely unchanged. The trimmed shape's fill and outline
are built from the clipped polygon. If the new shape is fully consumed by existing markers,
placement is aborted and no marker is left on the map.

**Difference**

Punches a virtual cutter shape into every overlapping existing Shape marker without placing
any new marker (`GuidesLinesApi.apply_shape_difference`). The overlapping area is removed
from each affected marker's outline; their fills and outlines are rebuilt from the resulting
clipped polygons. Acts as a no-op when no existing markers overlap the click position.

#### Additional behaviours

- **Live preview** — a translucent shape polygon follows the cursor while the mode is active,
  mirroring the current GuidesLines Shape parameters. Floor and Wall/Path textures
  follow the room settings, including No fill, offsets and template transforms.
  Boolean modes show the placement footprint rather than the final boolean result.
- **Grid snap** — click position is snapped to the Dungeondraft grid when *IsSnapping* is
  enabled. The optional **Lievven.Snappy_Mod** is detected automatically at map load and used
  for custom snap intervals when present.

---

## Requirements

| Dependency | Minimum version |
|------------|----------------|
| [CreepyCre._Lib](https://github.com/CreepyCre/_Lib) | any |
| [GuidesLines](https://github.com/ChosonDev/GuidesLines) | **v2.4.5+** |

Optional: **Lievven.Snappy_Mod** — detected automatically; no configuration needed.  
Optional: **[ColourAndModifyThings](https://github.com/Uchideshi/ColourAndModifyThings)** — enables path color picker in Path Builder and Room Builder (color persists across map reloads).

BuildingPlanner 1.3.0 requires GuidesLines 2.4.5 or later, including its template,
geometry and history-capture APIs. Dungeondraft's manifest dependency list records
mod IDs only; install the required GuidesLines version separately. Missing API
capabilities disable the affected preview and placement before changing the map.

## Installation

1. Install [CreepyCre._Lib](https://github.com/CreepyCre/_Lib)
2. Install [GuidesLines](https://github.com/ChosonDev/GuidesLines) v2.4.5+
3. Download the latest `BuildingPlanner.zip` from [Releases](../../releases)
4. Unzip into your Dungeondraft mods folder

## Development

```bash
git clone --recurse-submodules https://github.com/ChosonDev/BuildingPlanner
```

Dependencies live in `dependencies/` as git submodules.

Standalone tests run original mod scripts with Godot 3.4 and GUT 7.4.3:

```powershell
python tests/run.py --setup
python tests/run.py
```

See [tests/README.md](tests/README.md) for setup, coverage, failure-mode checks
and remaining Dungeondraft validation.

## License

MIT — see [LICENSE.md](LICENSE.md)
