# Building Planner

**Version:** 1.2.5
**Author:** Choson  
**Depends on:** [CreepyCre._Lib](https://github.com/CreepyCre/_Lib) · [GuidesLines](https://github.com/ChosonDev/GuidesLines) (v2.2.0+)

---

Generate Dungeondraft map content directly from [GuidesLines](https://github.com/ChosonDev/GuidesLines) markers.
Select the **Building Planner** tool in the *Design* category of the Dungeondraft toolbar,
then choose a mode from the sidebar.

## Features

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

---

### Path Builder
Click anywhere inside a Shape marker to trace a **closed path** along its outline.
Nearby Path markers use the same 100-world-unit nearest-marker check as Wall
Builder. Open markers retain their endpoints; closed markers close the path.
Crossing and collinear polylines are supported. Older GuidesLines APIs without
the geometry query retain the Shape workflow.

Configurable settings in the sidebar:

| Setting | Details |
|---------|---------|
| Path texture | Scrollable grid of all installed path textures (sourced from PathTool) |
| Color | ColorPicker — modulates the path texture tint *(requires ColourAndModifyThings; disabled otherwise)* |
| Width | Path width scale (0.1–10.0) |
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
using the current GuidesLines Shape parameters (radius, angle, sides) as the room footprint.

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

**Merge** *(requires GuidesLines v2.2.5+)*  
Unions the virtual shape with every overlapping existing Shape marker using
`GuidesLinesApi.place_shape_merge()`. The fill and wall for every affected polygon are
rebuilt from scratch to reflect the new merged geometry. Old fills and walls belonging to
absorbed markers are removed automatically.  
Falls back to Single (marker kept) when there are no overlapping markers.

**Conforming** *(requires GuidesLines v2.2.5+)*  
Places the new shape intact while **denting** every overlapping existing Shape marker to
accommodate it (`GuidesLinesApi.place_shape_conforming` — Difference applied to existing
markers only). The new shape's fill and outline are built normally; each dented marker's
fill and outline are rebuilt from its new clipped polygon.  
Falls back to Single (marker kept) when there are no overlapping markers.

**Wrapping** *(requires GuidesLines v2.2.5+)*  
Places a new Shape marker whose own outline is **trimmed** wherever it overlaps existing
Shape markers (`GuidesLinesApi.place_shape_wrapping` — Difference applied to the new shape
only). Existing markers are left completely unchanged. The trimmed shape's fill and outline
are built from the clipped polygon. If the new shape is fully consumed by existing markers,
placement is aborted and no marker is left on the map.

**Difference** *(requires GuidesLines v2.2.5+)*  
Punches a virtual cutter shape into every overlapping existing Shape marker without placing
any new marker (`GuidesLinesApi.apply_shape_difference`). The overlapping area is removed
from each affected marker's outline; their fills and outlines are rebuilt from the resulting
clipped polygons. Acts as a no-op when no existing markers overlap the click position.

#### Additional behaviours

- **Live preview** — a translucent shape polygon follows the cursor while the mode is active,
  mirroring the current GuidesLines Shape parameters.
- **Grid snap** — click position is snapped to the Dungeondraft grid when *IsSnapping* is
  enabled. The optional **Lievven.Snappy_Mod** is detected automatically at map load and used
  for custom snap intervals when present.

---

## Requirements

| Dependency | Minimum version |
|------------|----------------|
| [CreepyCre._Lib](https://github.com/CreepyCre/_Lib) | any |
| [GuidesLines](https://github.com/ChosonDev/GuidesLines) | **v2.2.0+** (v2.2.5+ for Merge, Conforming, Wrapping, and Difference modes) |

Optional: **Lievven.Snappy_Mod** — detected automatically; no configuration needed.  
Optional: **[ColourAndModifyThings](https://github.com/Uchideshi/ColourAndModifyThings)** — enables path color picker in Path Builder and Room Builder (color persists across map reloads).

The unreleased Room Builder changes require the matching local GuidesLines
`begin_history_capture()` / `end_history_capture()` API and explicit
`place_shape_marker_plain()` placement for Single and Merge fallback. Use both
updated mod sources together. Missing capabilities disable the affected preview
and placement before changing the map. No dependency pin or version
has been updated by this development change.

## Installation

1. Install [CreepyCre._Lib](https://github.com/CreepyCre/_Lib)
2. Install [GuidesLines](https://github.com/ChosonDev/GuidesLines) v2.2.0+
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
