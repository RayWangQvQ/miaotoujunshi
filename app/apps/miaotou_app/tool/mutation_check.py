#!/usr/bin/env python3
"""Mutation harness for the panel wiring's guards.

The repository's rule is that a guard nobody has broken is not known to work, so
each mutation below breaks the wiring on purpose, runs the suite, and records
**which** test went red. A mutation that leaves everything green means the guard it
was aimed at does not exist.

`panel_wiring_test.dart` exists because the two panel entry points were three
copies of the same six calls before it, and the copies had drifted where it
mattered: Android alone has to tell its host that the panel engine resumed. The
mutations below are that drift, reintroduced one at a time.

Run from the application package directory:

    python3 tool/mutation_check.py            # all of them
    python3 tool/mutation_check.py 2 4        # just these (1-based)

This one runs `flutter test --no-pub` on a single test file rather than the whole
suite, so it is minutes rather than an afternoon; `--no-pub` because the workspace
is already resolved and an implicit re-resolve turns a package-mirror outage into
"baseline is not green".
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[1]

# The file the whole harness aims at, and the one test file that answers for it.
WIRING = "lib/src/capability_registry.dart"
SUITE = "test/panel_wiring_test.dart"

# A Windows User-scope PUB_HOSTED_URL points at an unreachable corporate host in
# this environment, which makes `flutter test` fail to resolve before it runs
# anything. Pinned per run rather than inherited.
ENV = {**dict(os.environ), "PUB_HOSTED_URL": "https://pub.dev"}


@dataclass(frozen=True)
class Mutation:
    number: int
    name: str
    path: str
    old: str
    new: str
    expect_red: str

    def apply(self) -> Path:
        """Break the wiring, and return the file's original contents."""
        target = PACKAGE / self.path
        text = target.read_text(encoding="utf-8")
        if text.count(self.old) != 1:
            raise SystemExit(
                f"mutation {self.number} ({self.name}) does not apply cleanly: "
                f"{self.path} contains its target text {text.count(self.old)} "
                f"time(s), expected exactly 1. Either the wiring was refactored or "
                f"the mutation is ambiguous — fix the mutation, not the search."
            )
        target.write_text(text.replace(self.old, self.new, 1), encoding="utf-8")
        return target

    @staticmethod
    def restore(target: Path, original: str) -> None:
        target.write_text(original, encoding="utf-8")

    def occurrences(self) -> int:
        return (PACKAGE / self.path).read_text(encoding="utf-8").count(self.old)


MUTATIONS = (
    Mutation(
        1,
        "the port hands out another port's main channel",
        WIRING,
        "  Port.windows => PanelWiring(\n"
        "    mainChannel: WindowsPanelMainChannel.new,",
        "  Port.windows => PanelWiring(\n"
        "    mainChannel: AndroidPanelMainChannel.new,",
        "each port hands out its own main channel",
    ),
    Mutation(
        2,
        "macOS starts free instead of inset",
        WIRING,
        "    firstRun: _insetCorner,\n  ),\n  Port.windows",
        "    firstRun: _freePlacement,\n  ),\n  Port.windows",
        "the ball starts in a corner on Android and macOS and free on Windows",
    ),
    Mutation(
        3,
        "Android is not told the panel engine resumed",
        WIRING,
        "      markResumed: true,",
        "      markResumed: false,",
        "the panel engine gets its window and says it is up",
    ),
    Mutation(
        4,
        "every port is told the panel engine resumed",
        WIRING,
        "      markResumed: false,",
        "      markResumed: true,",
        "macOS is not told the engine resumed",
    ),
    Mutation(
        5,
        "the main window announces itself as the panel",
        WIRING,
        "  if (await bootstrap.role() == PanelEngineRole.main) {\n    return null;\n  }",
        "  if (false) {\n    return null;\n  }",
        "the main window is not a panel engine",
    ),
    Mutation(
        6,
        "the frame goes down before the appearance",
        WIRING,
        "  await channel.pushAppearance(panel.appearance);\n"
        "  await channel.push(panel.current);",
        "  await channel.push(panel.current);\n"
        "  await channel.pushAppearance(panel.appearance);",
        "both values go down, appearance first",
    ),
    Mutation(
        7,
        "the saved placement is ignored in favour of the first-run corner",
        WIRING,
        "    anchor: saved?.anchor ?? firstRun.anchor,\n"
        "    dx: saved?.dx ?? firstRun.dx,\n"
        "    dy: saved?.dy ?? firstRun.dy,",
        "    anchor: firstRun.anchor,\n    dx: firstRun.dx,\n    dy: firstRun.dy,",
        "a placement the user dragged wins over the first-run corner",
    ),
    Mutation(
        8,
        "the panel's commands are read but not acted on",
        WIRING,
        "    if (command.kind == PanelCommandKind.close) {\n"
        "      unawaited(floating.hide());\n    }",
        "    if (false) {\n      unawaited(floating.hide());\n    }",
        "a close from the panel hides the window",
    ),
)


def preflight(selected: list[Mutation]) -> list[str]:
    """Report every mutation whose target text has drifted, before running anything.

    `apply` already refuses a target it cannot find, but it runs one mutation at a
    time inside the loop, after a green baseline and after every earlier mutation
    has already paid for a suite run — so three drifted targets are discovered as
    three separate failures at three separate times. This costs one file read each
    and cannot report a partial list that looks complete.
    """
    problems: list[str] = []
    for mutation in selected:
        target = PACKAGE / mutation.path
        if not target.is_file():
            problems.append(
                f"mutation {mutation.number} ({mutation.name}) names "
                f"{mutation.path}, which does not exist"
            )
            continue
        count = mutation.occurrences()
        if count != 1:
            problems.append(
                f"mutation {mutation.number} ({mutation.name}) does not apply "
                f"cleanly: {mutation.path} contains its target text {count} "
                f"time(s), expected exactly 1"
            )
    return problems


def run_suite() -> tuple[int, str]:
    """`panel_wiring_test.dart` alone. Returns (exit code, output)."""
    result = subprocess.run(
        [shutil.which("flutter") or "flutter", "test", "--no-pub", SUITE],
        cwd=PACKAGE,
        env=ENV,
        capture_output=True,
        text=True,
        timeout=900,
    )
    return result.returncode, result.stdout + result.stderr


def red_tests(output: str) -> set[str]:
    """The names of the tests that failed, as `[E]` lines report them."""
    names = set()
    for line in output.splitlines():
        if "[E]" not in line:
            continue
        _, _, tail = line.partition(": ")
        names.add(tail.split(" [E]")[0].strip())
    return names


def main(argv: list[str]) -> int:
    wanted = {int(a) for a in argv[1:]} if len(argv) > 1 else None
    selected = [m for m in MUTATIONS if wanted is None or m.number in wanted]
    if not selected:
        print("no such mutation", file=sys.stderr)
        return 2

    problems = preflight(selected)
    if problems:
        print(
            f"{len(problems)} mutation(s) no longer match the code they were "
            f"written against:",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print(
            "\nFix the mutation to match the implementation — do not relax the "
            "match. A mutation that has drifted is a guard nobody has broken, "
            "which is the one thing this tool exists to rule out.",
            file=sys.stderr,
        )
        return 2

    code, output = run_suite()
    if code != 0:
        print("baseline is not green; fix that before mutating", file=sys.stderr)
        print(output[-4000:], file=sys.stderr)
        return 2
    print("baseline green\n")

    survivors: list[tuple[Mutation, set[str]]] = []
    for mutation in selected:
        target = PACKAGE / mutation.path
        original = target.read_text(encoding="utf-8")
        mutation.apply()
        try:
            code, output = run_suite()
        finally:
            mutation.restore(target, original)
        # Post-condition: the file is byte-for-byte what it was. A run that ends
        # with a mutated working tree is worse than no run, because the next green
        # suite would be green over the wrong code.
        if target.read_text(encoding="utf-8") != original:
            raise SystemExit(
                f"mutation {mutation.number} did not restore {mutation.path}; the "
                f"working tree is now mutated. Restore it from git before trusting "
                f"any result from this harness."
            )
        failed = red_tests(output)
        caught = any(mutation.expect_red in name for name in failed)
        mark = "RED " if code != 0 else "GREEN"
        print(f"{mutation.number:>2}. {mutation.name}")
        print(f"    suite: {mark}")
        if caught:
            hit = sorted(n for n in failed if mutation.expect_red in n)
            print(f"    caught by: {hit[0]}")
        elif code != 0:
            print(
                f"    red, but not by the expected test. Other failures: "
                f"{sorted(failed)[:3]}"
            )
            survivors.append((mutation, failed))
        else:
            print(
                f"    NOT CAUGHT — expected a test named like "
                f"{mutation.expect_red!r}"
            )
            survivors.append((mutation, failed))

    print()
    if survivors:
        print(f"{len(survivors)} mutation(s) not caught:")
        for mutation, _ in survivors:
            print(f"  {mutation.number}. {mutation.name}")
        return 1
    print(f"all {len(selected)} mutations caught")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
