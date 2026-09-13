#!/usr/bin/env python3
"""Import and run scene suites, treating Godot script errors as failures too."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parent
if os.name == "nt":
    COMMAND = [os.environ.get("GODOT_BIN", "godot"), "--path", str(PROJECT)]
else:
    COMMAND = [str(PROJECT / "godot.sh")]


def run_check(name, arguments, marker=None):
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as output:
        try:
            result = subprocess.run(
                COMMAND + ["--audio-driver", "Dummy"] + arguments,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=60,
                check=False,
            )
        except (subprocess.TimeoutExpired, OSError) as error:
            print(f"FAIL {name}: {error}", file=sys.stderr)
            return False
        output.seek(0)
        log = output.read()
    script_errors = "ERROR:" in log
    summary = re.search(rf"{re.escape(marker)}: \d+ checks, 0 failures", log) if marker else None
    passed = result.returncode == 0 and not script_errors and (marker is None or summary)
    if not passed:
        print(f"FAIL {name}: exit={result.returncode}", file=sys.stderr)
        # Keep the first diagnostic (root cause), without thousands of follow-on errors.
        print("\n".join(log.splitlines()[:65]), file=sys.stderr)
        return False
    print(summary.group(0) if summary else f"PASS {name}")
    return True


def main():
    if not run_check("Godot import", ["--headless", "--editor", "--quit"]):
        return 1
    for suite, marker in [("smoke", "ABYSS SMOKE"), ("weapons", "ABYSS WEAPONS"),
                          ("campaign", "ABYSS CAMPAIGN"), ("story_locale", "ABYSS STORY"),
                          ("production", "ABYSS PRODUCTION"), ("checkpoints", "ABYSS CHECKPOINTS"),
                          ("animation", "ABYSS ANIMATION"), ("presentation", "ABYSS PRESENTATION"),
                          ("aiming", "ABYSS AIMING"), ("coop", "ABYSS COOP"),
                          ("level_design", "ABYSS LEVEL DESIGN"), ("campaign_expansion", "ABYSS EXPANSION"),
                          ("legacy_campaign", "ABYSS LEGACY CAMPAIGN"), ("balance", "ABYSS BALANCE"),
                          ("reward_checkpoints", "ABYSS REWARD CHECKPOINTS"), ("map_art", "ABYSS MAP ART"),
                          ("build_info", "ABYSS BUILD INFO"), ("build_menu", "ABYSS BUILD MENU"), ("settings_menu", "ABYSS SETTINGS MENU")]:
        if not run_check(suite, ["--headless", "--script", f"res://tests/{suite}.gd"], marker):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
