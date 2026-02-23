# Building Planner

**Version:** 1.0.0  
**Author:** Choson  
**Depends on:** [CreepyCre._Lib](https://github.com/CreepyCre/_Lib) · [GuidesLines](https://github.com/ChosonDev/GuidesLines) (v2.2.0+)

---

Generate Dungeondraft map content directly from [GuidesLines](https://github.com/ChosonDev/GuidesLines) markers.

## Features

### Pattern Fill ✔
Click on a Shape marker while Pattern Fill mode is active to fill its interior with any
Dungeondraft terrain pattern. Configure color, rotation, layer, and outline in the sidebar.

### Wall Builder *(coming soon)*
Trace the outline of a Shape or Path marker with walls.
Supports closed loops (Shape) and open segments (Path).

### Mirror Mode *(coming soon)*
Activate an axis by selecting a Line marker. Everything placed while Mirror Mode is active
is automatically duplicated on the opposite side.

## Requirements

- [CreepyCre._Lib](https://github.com/CreepyCre/_Lib)
- [GuidesLines](https://github.com/ChosonDev/GuidesLines) **v2.2.0+**

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
