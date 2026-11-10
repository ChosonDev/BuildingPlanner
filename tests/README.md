# BuildingPlanner standalone tests

Tests execute original BuildingPlanner scripts in an isolated Godot CLI resource
root. No `project.godot`, runtime dependency checkout or executable API stubs are
needed. This is the initial suite, not full feature coverage.

## Project passport

| Field | Value |
| --- | --- |
| Target | `Choson.BuildingPlanner` 1.2.9, current checkout including local changes |
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
