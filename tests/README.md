# BuildingPlanner standalone tests

Tests execute original BuildingPlanner scripts in an isolated Godot CLI resource
root. No `project.godot`, runtime dependency checkout or executable API stubs are
needed. This is the initial suite, not full feature coverage.

## Project passport

| Field | Value |
| --- | --- |
| Target | `Choson.BuildingPlanner` 1.2.5, current checkout including local changes |
| Purpose | Detect loading, geometry, registry, history and early API regressions |
| Environment | Godot `3.4.stable.official.206ba70f4`; Python 3.8+ standard library |
| Test dependency | GUT 7.4.3, commit `c11ba9daf49b2ec127d6113be89534dc9ee21873`, upstream `bitwes/Gut`, MIT |
| Location | `tests/`, versioned with BuildingPlanner, excluded from release archives |
| Inputs | Narrow API and Save/Load substitutes, dictionaries and real Godot Nodes |
| Isolation | Original scripts loaded directly; broken probes modify disposable copies only |
| Acceptance | Complete nonempty selected set, passing assertions, no pending, engine errors or timeout |
| Identity | Git revision/status, runtime/test SHA-256 hashes, runtime policy hash and actual engine version in each report |

## Prepare and run

From the workspace root:

```powershell
python Mods/BuildingPlanner/tests/run.py --setup
python Mods/BuildingPlanner/tests/run.py
python Mods/BuildingPlanner/tests/run.py --test test_roof
python Mods/BuildingPlanner/tests/run.py --keep-results 20
python Mods/BuildingPlanner/tests/check_runner.py
python Mods/BuildingPlanner/tests/check_runtime.py
```

Setup checks the existing `ExternalMods/Gut` checkout's pinned revision and clean
addon, then copies the unchanged addon with its MIT license to ignored
`tests/addons/`. It never downloads or updates upstream code. Supply
`--gut-source PATH` if the checkout is elsewhere.

The default engine is workspace `Godot/Godot_v3.4-stable_win64.exe`. Override it
with `GODOT_BIN` (all commands) or `--godot PATH` (main runner). `--timeout SECONDS`
defaults to 30. The Windows `--no-window` engine still needs a graphics driver.
Paths are resolved from the runner, independently of the current directory.

Each invocation writes `results/<UUID>/run.json`, `output.log` and `junit.xml`.
Reports are retained by default. Use `--keep-results N` to remove older completed
runs after execution, retaining the N newest by report modification time, regardless
of success or failure. Running reports, malformed metadata, unrecognized folders
and redirected directories are preserved. Existing reports are not cleaned until
this option is explicitly supplied. Archive evidence you need before enabling it.
Use the Python wrapper for acceptance: GUT 7 alone can return success after a
runtime error following a passing assertion. Missing or malformed reports,
incomplete selection, skipped or assertion-free cases and engine errors fail.

## Coverage

The suite covers runtime smoke checks, geometry, native creation collaborators,
compound room history, independent textures and tool lifecycle regressions.

- All 12 runtime scripts compile and their reviewed outer constructors run
  off-tree. Owned Nodes are freed. Nested history records have a separate workflow.
- Inventory rejects new unclassified scripts, duplicate policies and invalid
  source roots. Manifest fields, entry type and toolbar icon existence are checked.
- Geometry checks reject malformed/non-finite/degenerate/crossing polygons and
  preserve winding, translated geometry, hole bridges and tangent contours.
- Optional CAMT color storage preserves other records/settings, supplies defaults
  and survives JSON encoding/decoding using Godot 3's actual color format.
- Registry checks cover copied input arrays, replacement, negative IDs, stale
  nodes, deferred deletion and clearing associations without deleting scene nodes.
- Feature contracts reject absent, old or unready APIs and invalid polygon
  responses before accessing map objects. Room preview checks offsets, minimum
  scale and clearing. Roof checks cover seam closure and known expand/inset bounds.
- Fill/path/roof history executes undo, redo and both drop directions using
  controlled Save/Load nodes. Paths retain color, CAMT data and their original
  level. Actual native serialization and the host HistoryApi remain excluded.
- Standalone wall history records one action, uses Manual wall semantics and
  restores the original level and tree order through the host's void LoadWall
  contract. Roof checks cover pixel conversion, retained panel choices, shared
  level sunlight (including disabled shade), radians at the node boundary and
  undo/redo of lighting and Under sorting.
- Asset checks cover No fill, thumbnail-based pattern tint, raw PNG repeat flags,
  selection without native callbacks and complete owned path catalogs despite
  changes to the host's search filter. Native C# implementations require host acceptance.
- Path creation records the directly loaded node through a controlled HistoryApi;
  native load failures leave no nodes or history records.
- Tool checks cover disabled updates, freed overlays, map-scoped registry cleanup,
  signal teardown, initial grid callbacks, filtering, preview snapping and canvas
  boundaries. Real mouse routing and native asset menus still require Dungeondraft.

`runtime_files.json` is the constructor/source policy. The entry loader prepends
`var Global = {}` and `var Script=null` in memory for `BuildingPlanner.gd` only;
it does not change original code. Ordinary modules must start with `extends`.
Constructing the entry does not execute `start()` or initialize host services.

`check_runner.py` checks report retention in a disposable directory and eight real executions: success, failure, pending,
assertion-free case, syntax error, runtime error after a passing assertion, empty
selection and timeout. `check_runtime.py` checks a valid disposable copy plus nine
broken variants: syntax, constructor, classification, missing root, empty policy,
escaping root, entry-source policy, manifest and resource. Expected broken reports
are diagnostic artifacts; the self-check command succeeds only if they are rejected.

Add flat `unit/test_*.gd` files extending `res://addons/gut/test.gd`, with plain
nonparameterized `func test_*()` methods. Inner test classes and parameterized
cases require extending the runner's expected-case collector first. Helper classes
are supported. Keep generated addons, logs, reports and caches ignored.

## Remaining host validation and next coverage

Dungeondraft validation remains outstanding: use a scratch map with `_Lib` and
GuidesLines enabled; create fills, walls, paths, roofs and rooms; undo/redo;
save/reopen; switch maps/tools; check optional integrations and late API setup.
These tests do not prove rendering, native node IDs, SelectTool registration,
installed dependency compatibility or native map persistence.

Room workflows cover all five modes with both outlines, absorbed/consumed markers,
Merge fallback, adjacent undo/redo, scene ordering, setting forwarding and rollback
on partial failure. Texture tests cover panel-to-feature routing, builder selection
and native raw-PNG cache reuse. Manual acceptance remains delegated to the user.

The current suite has 103 tests. Recent regression coverage includes late API and
panel binding, per-level roof lighting, map texture invalidation, plain-marker
history, wheel overrides, CAMT readiness transitions, Merge on a new map level,
and direct native path data with translated coordinates and Under/Over ordering.
The latest audit regressions also check Hip roof initialization order, same-level
sunlight changes, explicit click coordinates, normalized negative rotations,
Single rooms without temporary marker history and mode-specific CAMT polling.
Path-marker tests exercise both builders with open/closed serialized polylines,
translated coordinates, repeatable undo/redo, Shape/legacy fallback, crossing and
collinear paths, duplicate vertices and malformed inputs rejected before mutation.

Audit regressions check logged contract failures, room rollback, empty layer-list
preservation, asset-loader diagnostics and shared Texture identity in isolated settings.

Refactoring regressions cover complete explicit feature settings, independent
before/after room style ownership, freed secondary levels, narrow shape-state
polling with legacy fallback, and the shared standalone history implementation.

Native history call signatures are checked with required `Save(copy)` parameters
for PatternShape, Pathway and Roof, and argument-free `Save()` for Wall. History
must explicitly pass `false` to retain native IDs. The extracted host declares
these signatures in `scripts/world/objects/{PatternShape,Pathway,Roof}.cs` and
`scripts/world/Wall.cs`; the Godot 3.4
[Mono call bridge](https://github.com/godotengine/godot/blob/3.4/modules/mono/csharp_script.cpp#L1574-L1607)
resolves methods by argument count. Earlier argument-free GDScript substitutes
did not exercise this boundary.

Crash follow-up on 2026-11-05: 104 tests / 1672 assertions passed
([report](results/d0d4c6a51eee4fd6b2adf40ab1debaf8/run.json)). Windows recorded a
native access violation during Single placement; the corrected Save calls still
need host acceptance. Debug logs now bracket native history capture and confirm
compound history registration, to locate any remaining failure.

## Audit review - 2026-11-05

The supplied audit was checked against both current worktrees. Its original
snippets describe earlier implementations; the current decisions are:

| Item | Current implementation and evidence |
| --- | --- |
| 1.1 Template defaults | Parametric shapes require finite position, radius and angle plus valid sides; descriptor/template regressions run in GuidesLines. Primitive outlines retain their independent geometry contract. |
| 1.2 Room failures | Missing shape parameters reject placement; clicks log failures while preview stays quiet. Missing ownership/style metadata aborts and rolls back marker edits before native cleanup. Room regressions cover these failures. |
| 1.3 Empty layers | An available LayerApi returning an empty list preserves the current selection and logs an error. Defaults apply only before the API/map is available. Lifecycle tests exercise the actual refresh path. |
| 1.4 Geometry responses | Ordinary misses remain quiet; malformed API responses and invalid outlines produce diagnostics and abort. Feature and path-marker tests distinguish these cases. |
| 1.5 No fill | Room mode skips optional fill creation. Standalone fill rejects a missing texture with a diagnostic. Feature and room tests cover both. |
| 1.6 History ownership | Native history requires a live node; room snapshots verify container ancestry before recording an owner. History tests cover original and freed secondary levels. |
| 2.1 Standalone history | NativeObjectRecord shares snapshot lifetime, map guards and replay. Roof records retain their required shared sunlight behavior. History tests cover each native kind. |
| 2.2 Placement flags | Explicit placement policy arguments replace temporary conform/wrap UI mutations, including redo. GuidesLines tests observe unchanged flags during placement and replay. |
| 2.3 Overlay setup | Update contains one overlay creation check. |
| 3.1 Frame allocations | Room polling uses the five-field get_shape_state API with legacy fallback. Preview arguments and the GuidesLines preview dictionary reuse storage; click arguments remain a separate snapshot across callbacks. Tests cover API freshness and storage ownership. |
| 3.2 Temporary builders | Explicit get_settings methods and optional creation settings reuse the existing builders. Tests cover settings completeness and preserved room styles after cuts. |
| 3.3 Registry/history copies | Registry hits avoid eagerly allocated defaults. History owns the already detached settings snapshot and caches the involved levels. Public snapshot copies and native Save/Load copies remain necessary to isolate mutable data; tests verify that isolation. |
| 3.4 Asset indices | Catalog paths use an Array with bounds checks and native find. Asset/lifecycle tests cover selection and filtering. |
| 4.1 UI encapsulation | Tool accesses public UI methods for binding, selection, mode refresh, roof synchronization and shutdown. Lifecycle regressions cover these paths. |
| 4.2 Registry level schema | Retained: the small explicit level list supports rebuilding across levels and is checked against actual node ancestry when serializing. Replacing it with per-node metadata would introduce another ownership schema without fixing a demonstrated defect. |
| 4.3 Artifacts/docs | Explicit --keep-results bounds retained terminal runs. Retention self-checks preserve running and unknown artifacts. This review lives in the existing README, with no temporary attachment paths or link to the removed audit file. |

Standalone checks cannot establish native Dungeondraft persistence or rendering.
Host acceptance remains the scratch-map workflow described above; the user will
perform it later. No dependency pin, manifest version or release is changed as
part of this audit follow-up.

Verified on 2026-11-05: BuildingPlanner `run.py` passed 103 tests / 1660 assertions
([report](results/3fdbbf660cda45c2b54f2f2493d103c1/run.json)); GuidesLines `run.py`
passed 88 tests / 1843 assertions
([report](../../GuidesLines/tests/results/8376291a51614532a513499334d66b3e/run.json)).
Both suites reported no failing, risky or pending tests. BuildingPlanner
`check_runner.py` passed its eight real GUT scenarios and the retention check;
`git diff --check` passed in both repositories. Reports are ignored local evidence
and may later be removed by the explicit retention option.
