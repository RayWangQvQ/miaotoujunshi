#!/usr/bin/env python3
"""Mutation harness for #15's macOS-only guards.

The repository's rule is that a guard nobody has broken is not known to work, so
each mutation below breaks one implementation on purpose, runs the suite, and
records **which** test went red. A mutation that leaves everything green means
the guard it was aimed at does not exist.

**This file used to carry every mutation for #15.** The storage modules it mutated
— preferences, the knowledge base, the memory store, the JSON document and the
payload reader — are `miaotou_capabilities_shared`'s now, so those mutations moved
with them into that package's own harness. What is left here is what this package
still owns: its Keychain, its container directory, its payload root, and its build.
A mutation for a shared module would have to reach across into another package's
`lib/`, and it would be caught by a suite that lives there — a harness pointing at
the wrong tree.

Run from the macOS package directory:

    python3 tool/mutation_check.py            # all of them
    python3 tool/mutation_check.py 3 7        # just these (1-based)

**This one is a POSIX tool.** Several of the guards below run the Xcode build phase
through `/bin/sh`, so the baseline is not green on Windows and the harness stops
there with `baseline is not green` — which is the correct answer, not a bug to work
around. The shared package's harness (`dart test`, no shell anywhere) runs on every
platform this repository is developed on, which is why the storage guards live
there now.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


PACKAGE = Path(__file__).resolve().parents[1]

# `flutter test` needs to reach its own tester process over a loopback socket, and
# this environment sets HTTP_PROXY for everything, which the tester honours and
# then fails on. Cleared per run rather than inherited.
#
# `PUB_HOSTED_URL` is pinned for the sibling harness's reason: a Windows User-scope
# value points at an unreachable corporate host here, and `flutter test` resolves
# before it runs anything, so the baseline would report a package-mirror socket
# error instead of the POSIX guards that actually make it red on Windows.
ENV = {
    **dict(os.environ),
    "NO_PROXY": "localhost,127.0.0.1",
    "no_proxy": "localhost,127.0.0.1",
    "PUB_HOSTED_URL": "https://pub.dev",
}
for _name in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
    ENV.pop(_name, None)


def _flutter() -> str:
    """The Flutter launcher, from `PATH` when it is there.

    It used to be pinned to `~/dev/flutter-3.47.6/bin/flutter`, which was the
    migration's toolchain and is not every machine's. The version this workspace
    targets is declared in `.github/workflows/flutter.yml`; this only has to find
    *a* launcher, and the suite is what says whether it is the right one.
    """
    return shutil.which("flutter") or str(
        Path.home() / "dev/flutter-3.47.6/bin/flutter"
    )


FLUTTER = _flutter()


@dataclass(frozen=True)
class Mutation:
    number: int
    name: str
    path: str
    old: str
    new: str
    expect_red: str

    def apply(self) -> Path:
        """Break the implementation, and return the file's original contents.

        The original is **snapshotted**, not reconstructed by substituting the
        mutation back out. Reverse substitution is only correct when the mutated
        text is unique in the file, and several of these mutations replace a
        fragment that occurs twice (`if (root.isEmpty) {` is the guard in both the
        container and the payload tree). Getting that wrong silently leaves a
        mutated file behind, which is how a mutation run corrupts a working tree —
        so the snapshot is the only mechanism used, and a post-condition check
        below refuses to report a result otherwise.
        """
        target = PACKAGE / self.path
        text = target.read_text(encoding="utf-8")
        if text.count(self.old) != 1:
            raise SystemExit(
                f"mutation {self.number} ({self.name}) does not apply cleanly: "
                f"{self.path} contains its target text "
                f"{text.count(self.old)} time(s), expected exactly 1. Either the "
                f"implementation was refactored or the mutation is ambiguous — "
                f"fix the mutation, not the search."
            )
        target.write_text(text.replace(self.old, self.new, 1), encoding="utf-8")
        return target

    @staticmethod
    def restore(target: Path, original: str) -> None:
        target.write_text(original, encoding="utf-8")

    def occurrences(self) -> int:
        """How many times this mutation's target text appears in its file."""
        return (PACKAGE / self.path).read_text(encoding="utf-8").count(self.old)


MUTATIONS = (
    # -- what this package's Dart still answers for --------------------------
    Mutation(
        1,
        "the keychain: keys() answers a value as well as a name",
        "lib/src/secrets.dart",
        "Future<Set<String>> keys() async => (await _native.keychainKeys()).toSet();",
        "Future<Set<String>> keys() async => (await _native.keychainKeys()).toSet()\n      ..add('sk-leaked');",
        "keys() names the configured routes",
    ),
    Mutation(
        2,
        "the container: a store with no directory writes to the working directory",
        "lib/src/container_documents.dart",
        """    if (root.isEmpty) {
      throw StateError(""",
        """    if (false) {
      throw StateError(""",
        "an answer with no path in it is refused",
    ),
    Mutation(
        3,
        "the payload: the resource root is asked on every read",
        "lib/src/payload.dart",
        # The mutation follows the behaviour it protects — the caching — rather
        # than where the caching used to be written. It moved into `resourceRoot`'s
        # body when that gained its empty-root guard, so it is an `await` on a
        # local instead of the whole body of an arrow function.
        "final String root = await (_root ??= _native.resourceRoot());",
        "final String root = await _native.resourceRoot();",
        "the resource root is asked once",
    ),
    Mutation(
        4,
        "the payload: an empty root is joined onto instead of refused",
        "lib/src/payload.dart",
        """    if (root.isEmpty) {
      throw StateError(""",
        """    if (false) {
      throw StateError(""",
        "an empty root from any implementation is refused where it is used",
    ),
    # -- the build and the two native halves ---------------------------------
    Mutation(
        5,
        "the Keychain: the listing query asks for data",
        "macos/miaotou_capabilities_macos/Sources/miaotou_capabilities_macos/"
        "KeychainStore.swift",
        "kSecReturnAttributes as String: true,\n            kSecMatchLimit as String: kSecMatchLimitAll,\n            kSecUseDataProtectionKeychain as String: true,\n        ]\n\n        var result: CFTypeRef?",
        "kSecReturnData as String: true,\n            kSecMatchLimit as String: kSecMatchLimitAll,\n            kSecUseDataProtectionKeychain as String: true,\n        ]\n\n        var result: CFTypeRef?",
        "the listing query asks for attributes and not for data",
    ),
    Mutation(
        6,
        "the Keychain: a query drops the data protection attribute",
        "macos/miaotou_capabilities_macos/Sources/miaotou_capabilities_macos/"
        "KeychainStore.swift",
        """            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]""",
        """            kSecAttrAccount as String: key,
        ]""",
        "every query asks for the data protection keychain",
    ),
    Mutation(
        7,
        "the sync: rsync becomes a copy, leaving deleted files behind",
        "../../apps/miaotou_app/macos/Runner/sync_shared_payload.sh",
        'rsync -a --delete "$REPO_ROOT/$tree/" "$RESOURCES/$tree/"',
        'rsync -a "$REPO_ROOT/$tree/" "$RESOURCES/$tree/"',
        "the sync is an rsync mirror",
    ),
    Mutation(
        8,
        "the sync: the assertion is looked for beside SRCROOT instead of in tool/",
        "../../apps/miaotou_app/macos/Runner/sync_shared_payload.sh",
        # Realigned from "the phase no longer calls the assertion" when F1 fixed
        # the path, and realigned again by ADR-0027, which moved the assertion into
        # the application's `tool/` and moved its interpreter from Python to the
        # Dart SDK Flutter already ships. The old claim was the weaker one:
        # `echo`-ing instead of calling is a change no path can hide, and the
        # build-phase test that *runs* the script already fails on it. Dropping the
        # `../tool/` step is the regression that actually happened — `SRCROOT` is
        # `…/macos` and the assertion is one level up and across — and it is caught
        # only by the tests that execute the phase, because the static
        # SRCROOT-shape test never reads this expression.
        '"$SRCROOT/../tool/validate_payload_keys.dart"',
        '"$SRCROOT/validate_payload_keys.dart"',
        "the build phase runs, and it passes",
    ),
    Mutation(
        9,
        "the payload map: a scene document is dropped from the key set",
        "../../apps/miaotou_app/tool/validate_payload_keys.dart",
        "_mapMapKeys = <String>['scene_knowledge'];",
        "_mapMapKeys = <String>[];",
        "the key set is derived from the domain and the payload map",
    ),
)


def preflight(selected: list[Mutation]) -> list[str]:
    """Report every mutation whose target text has drifted, before running anything.

    ## Why this is separate from `apply`

    `apply` already refuses a target it cannot find, and that refusal is what
    keeps a mutation from silently becoming a no-op. But `apply` runs *inside*
    the loop, one mutation at a time, after a green baseline and after every
    earlier mutation has already paid for a full suite run. A harness that only
    fails there reports one drifted mutation per run and says nothing about the
    rest, so three drifted targets are discovered as three separate failures at
    three separate times — and the second and third are never discovered at all
    if the first one is fixed and the run stops.

    Checking all of them up front turns "the seventh one is broken" into "these
    three are broken", costs one file read each instead of a suite run, and
    cannot report a partial list that looks complete.

    Silent failure is the worst outcome this tool has, because its entire claim
    is that every guard has been *seen* to go red. A mutation that quietly stops
    applying is a guard that quietly stops being checked, and the harness would
    still print its green summary.
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
    """The macOS package's whole suite. Returns (exit code, output).

    `--no-pub` because the workspace is already resolved by the time this runs
    (the README's own recipe is `flutter pub get` once, then test), and an
    implicit re-resolve turns a package-mirror outage into "baseline is not
    green" — a red baseline for a reason that has nothing to do with the guards
    this harness is here to break.
    """
    result = subprocess.run(
        [FLUTTER, "test", "--no-pub", "--reporter", "compact"],
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
        # `00:01 +12 -3: some group a test name [E]`
        _, _, tail = line.partition(": ")
        names.add(tail.split(" [E]")[0].strip())
    return names


def main(argv: list[str]) -> int:
    wanted = {int(a) for a in argv[1:]} if len(argv) > 1 else None
    selected = [m for m in MUTATIONS if wanted is None or m.number in wanted]
    if not selected:
        print("no such mutation", file=sys.stderr)
        return 2

    # Every target text is checked before the baseline runs, not lazily inside
    # the loop. A drifted mutation is a hard error — never a skip — because the
    # alternative is a harness that reports "all caught" while one of them
    # quietly stopped breaking anything.
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

    # A green baseline, so a red run below is attributable to the mutation.
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
        # with a mutated working tree is worse than no run, because the next
        # green suite would be green over the wrong code.
        if target.read_text(encoding="utf-8") != original:
            raise SystemExit(
                f"mutation {mutation.number} did not restore {mutation.path}; "
                f"the working tree is now mutated. Restore it from git before "
                f"trusting any result from this harness."
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
