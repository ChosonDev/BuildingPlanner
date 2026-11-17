# RoomTemplate audit — 2026-11-17

Scope: uncommitted RoomTemplate implementation, selection/UI synchronization,
texture loading, map persistence, saved geometry and optional CAMT behavior.

## Follow-up: saved templates missing from the dropdown

The user's Test map contains two valid serialized RoomTemplates. A read-only probe
loaded both through the real RoomTemplate parser in Godot (four assertions passed).
The failure is not missing serialized data in that inspected map.

`update_room_templates()` previously observed only World changes. A reproducible
lifecycle regression writes the map `mod` block to a temporary file, parses it,
and provides it after the destination World has already been observed. Previously
the dropdown stayed disabled with New template; the test failed. Now persistence
also watches the owned RoomTemplate data block, loads late-arriving data, and
rebuilds the dropdown. Its own normal/backup saves update the observed block so
they do not reload templates or reset selection.

The original round-trip check changed World and supplied map data together, so it
did not cover this ordering. The new check covers the distinct arrival and actual
temporary-file JSON round trip. Dungeondraft confirmation of this fix remains
outstanding; the user's map and installed mod copies were read without modification.

Follow-up validation: **174 tests and 3144 assertions passed**, report
`results/cc956082d0804736b8b0b016894d0596/run.json`; `git diff --check` passed.

## Findings fixed

1. **High: pattern resolution could abort template selection.**
   `apply_room_template()` used `GetAssetTexture("Patterns", path)` for every floor.
   The host `ModToolScript.GetAssetTexture` directly indexes
   `Master.Library[category].Reverse[path]`; `Library.Init` has a separate
   `Patterns Colorable` category. The existing PatternPanel also supports raw pack
   images through a cached image loader. Restore floors through that loader,
   retaining repeat/filter flags. Previous selection tests used empty texture paths
   and could not catch this failure.

2. **High: missing Wall/Path assets could throw before the promised atomic failure.**
   Check the native `GetAssetList` before calling `GetAssetTexture`. Resolve every
   texture before updating panels. A missing texture retains the selected template
   and all current settings and reports a UI error.

3. **Medium: selected shape state lagged until the next preview/click.**
   Refresh `gl_tool_state` immediately after successful selection and after returning
   to New template. That transition also cancels sampling and clears the old preview.

4. **Medium: restoring a template could bypass disabled optional Path coloring.**
   Reconcile CAMT availability after restoring panel fields; without CAMT the picker
   stays disabled and the effective Path color stays white. Saved template colors
   remain intact for subsequent use with CAMT installed.

5. **Medium: malformed optional geometry could pass validation and fail transforming.**
   Validate all optional coordinate arrays, including keys not required by the
   marker's type, before retaining the snapshot.

## Verification

- New A/B/A signal-driven selection regression uses cached floor textures outside
  the native Patterns index, a raw PNG, Wall/Path assets and distinct saved styles.
  It compares every style field with the active feature and applicable visible
  control, selected texture, color, sub-mode, outline, shape state and transforms.
- Missing native assets are rejected before native lookup and without partial edits.
- Existing checks cover JSON round trips, map changes, backup save signals,
  malformed-data preservation, independent transformed geometry, Add/Rename/Delete
  and missing textures. The geometry check now covers malformed optional arrays.
- `python Mods/BuildingPlanner/tests/run.py --timeout 60`: **173 tests passed,
  3131 assertions**, Godot 3.4 / GUT 7.4.3. Report:
  `results/aaf6599051fb40f79203c2b04d0fe8e7/run.json` (local ignored artifact).
- An earlier full run failed the existing modal-keyboard sampling test once.
  Its isolated rerun and the subsequent full suite passed without a code change.
  The cause of this input-test instability is unresolved; this audit does not
  claim it has been fixed.

## Host validation outstanding

No Dungeondraft session was exercised during this audit. On a scratch map:

1. Save two distinct styles, including a colorable/custom-pack pattern, then switch
   A/B/A and compare all visible fields and previews. Build a room with each.
2. Check Wall/Path outlines, No fill, and Path coloring with and without CAMT.
3. Save/reopen, switch maps/tools, rename/delete, and check undo/redo for placed rooms.
4. Reopen with an asset pack absent: switching must show an error without changing
   the current style or discarding saved templates.

Saved Line members remain finite map-clipped geometry supplied by the public
GuidesLines API at capture time; they do not become infinite guides on later maps.
Host rendering, actual asset-pack mounting and native map serialization still
require the checks above.
