"""Exercise real GUT failure modes; run after run.py --setup."""

import json
import os
import tempfile
from pathlib import Path

from run import DEFAULT_GODOT, ROOT, execute, prune_results


def check_retention():
    with tempfile.TemporaryDirectory() as directory:
        results = Path(directory)
        for index, status in enumerate(("passed", "failed", "timeout", "running")):
            path = results / f"{index:032x}"
            path.mkdir()
            (path / "run.json").write_text(json.dumps({
                "run_id": path.name, "status": status,
                "finished_at": "2026-11-05T00:00:00Z" if status != "running" else None,
            }), encoding="utf-8")
            os.utime(path / "run.json", (100 + index, 100 + index))
        unknown = results / ("f" * 32)
        unknown.mkdir()
        (unknown / "run.json").write_text("broken", encoding="utf-8")
        assert prune_results(results, 2) == 1
        assert not (results / ("0" * 32)).exists()
        assert all((results / f"{index:032x}").exists() for index in (1, 2, 3))
        assert unknown.exists()
        assert prune_results(results, 2) == 0
        try:
            prune_results(results, 0)
        except ValueError:
            pass
        else:
            raise AssertionError("Zero retention must be rejected")


def main():
    check_retention()
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    probes = {
        "passed": ('assert_eq(1, 1)', "passed"),
        "failed": ('assert_eq(1, 2)', "failed"),
        "pending": ('pending("required test")', "failed"),
        "risky": ('pass', "failed"),
        "parse": ('this is invalid gdscript', "failed"),
        "runtime": ('assert_true(true)\n\tvar value = null\n\tvalue.missing()', "failed"),
        "empty": (None, "failed"),
        "timeout": ('while true:\n\t\tpass', "timeout"),
    }
    for name, (body, expected) in probes.items():
        with tempfile.TemporaryDirectory(prefix="probe_", dir=cache) as directory:
            if body is not None:
                Path(directory, "test_probe.gd").write_text(
                    'extends "res://addons/gut/test.gd"\nfunc test_probe():\n\t' + body + '\n',
                    encoding="utf-8",
                )
            state = execute(DEFAULT_GODOT, Path(directory), timeout=3 if name == "timeout" else 30)
            assert state["status"] == expected, (name, state)
    print(f"Runner checks passed: {len(probes)} real GUT scenarios")


if __name__ == "__main__":
    main()
