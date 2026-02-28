# Building Planner

**Version:** 1.1.4  
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
| Layer | 0–9 (Dungeondraft pattern layer) |
| Outline | Toggles a border around the filled polygon |

---

### Wall Builder
Click anywhere inside a Shape marker to trace a **closed wall** along its outline.

Configurable settings in the sidebar:

| Setting | Details |
|---------|---------|
| Wall style | Scrollable grid of all installed wall textures (sourced from WallTool) |
| Color | ColorPicker — pre-filled with the style's default color |
| Shadow | Toggle wall shadow |
| Joint | Sharp / Bevel / Round corner type |

---

### Path Builder
Click anywhere inside a Shape marker to trace a **closed path** along its outline.

Configurable settings in the sidebar:

| Setting | Details |
|---------|---------|
| Path texture | Scrollable grid of all installed path textures (sourced from PathTool) |
| Color | ColorPicker — modulates the path texture tint *(requires ColourAndModifyThings; disabled otherwise)* |
| Width | Path width scale (0.1–10.0) |
| Smoothness | Bezier smoothing intensity (0.0–1.0 slider) |
| Layer | 0–9 (Dungeondraft path layer) |
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
Click anywhere inside a Shape or Path marker to place a **roof** along its outline.

Configurable settings in the sidebar:

| Setting | Details |
|---------|--------|
| Roof texture | Scrollable grid of all installed roof textures (sourced from RoofTool) |
| Width | Eave width in Dungeondraft units (5–500, default 50) |
| Type | Gable / Hip / Dormer |
| Layer | Over / Under (render-order sorting) |
| Placement mode | *Ridge along area* — outline is the ridge line; *Expand* — eave at outline, roof grows outward; *Inset* — eave at outline, roof grows inward |
| Shade | Toggles sunlight shading; exposes Sun Direction (0–360 °) and Contrast (0.0–1.0) sub-controls |

> **Roof placement is fully undoable** via Ctrl+Z / **History API**.

---

### Room Builder
One-click room creation — places a pattern fill **and** a closed outline simultaneously,
using the current GuidesLines Shape parameters (radius, angle, sides) as the room footprint.

Pattern settings and outline settings are configured independently in the sidebar.

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
| [GuidesLines](https://github.com/ChosonDev/GuidesLines) | **v2.2.0+** (v2.2.5+ for Merge mode) |

Optional: **Lievven.Snappy_Mod** — detected automatically; no configuration needed.  
Optional: **[ColourAndModifyThings](https://github.com/Uchideshi/ColourAndModifyThings)** — enables path color picker in Path Builder and Room Builder (color persists across map reloads).

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

## License

MIT — see [LICENSE.md](LICENSE.md)
