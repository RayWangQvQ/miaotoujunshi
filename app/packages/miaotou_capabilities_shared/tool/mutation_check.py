#!/usr/bin/env python3
"""Mutation harness for the shared modules' guards.

The repository's rule is that a guard nobody has broken is not known to work, so
each mutation below breaks one implementation on purpose, runs the suite, and
records **which** test went red. A mutation that leaves everything green means
the guard it was aimed at does not exist.

This harness used to live in `miaotou_capabilities_macos` and carried every
mutation for #15, including the ones aimed at the modules the three ports had each
written for themselves. Those modules are `miaotou_capabilities_shared` now, so the
mutations aimed at them moved here with them — a harness in a port package would
have had to reach across into another package's `lib/` to break them, and the
`miaotou_capabilities_macos` copy is trimmed to what that package still owns: its
Keychain, its container directory, its payload root, its build.

Run from the shared package directory:

    dart pub get
    python3 tool/mutation_check.py            # all of them
    python3 tool/mutation_check.py 3 7        # just these (1-based)

The suite is `dart test` rather than `flutter test`, because this package has no
Flutter in it — which is also why the whole run is a couple of minutes rather than
an afternoon.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


PACKAGE = Path(__file__).resolve().parents[1]

# A Windows User-scope PUB_HOSTED_URL points at an unreachable corporate host in
# this environment, which makes `dart test` fail to resolve before it runs
# anything. Pinned per run rather than inherited.
ENV = {**dict(os.environ), "PUB_HOSTED_URL": "https://pub.dev"}


def _dart() -> str:
    """The real Dart binary, whichever way this platform spells it.

    `dart` on `PATH` is a shell script on every platform. A POSIX `fork`/`exec`
    runs one happily; `CreateProcess` on Windows cannot, and says only
    "the system cannot find the file specified". So the SDK binary that the
    script wraps is preferred when it is there, which is also one process fewer
    per run.
    """
    found = shutil.which("dart")
    if found is None:
        return "dart"
    beside = Path(found).parent / "cache" / "dart-sdk" / "bin"
    for name in ("dart.exe", "dart"):
        candidate = beside / name
        if candidate.is_file():
            return str(candidate)
    return found


DART = _dart()


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
        fragment that occurs twice (`return count;` and the branches around it).
        Getting that wrong silently leaves a mutated file behind, which is how a
        mutation run corrupts a working tree — so the snapshot is the only
        mechanism used, and a post-condition check below refuses to report a
        result otherwise.
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
    # -- one named document --------------------------------------------------
    Mutation(
        1,
        "the document: a file that is not an object reads as an empty store",
        "lib/src/document.dart",
        """    if (decoded is! Map) {
      throw FormatException(
        '$name does not hold a JSON object; refusing to treat it as an empty '
        'store, because that would hide the loss',
        name,
      );
    }""",
        """    if (decoded is! Map) {
      return <String, Object?>{};
    }""",
        "a document that is not a JSON object is refused",
    ),
    Mutation(
        2,
        "the document: an empty file is parsed instead of reading as nothing",
        "lib/src/document.dart",
        """    if (text == null || text.trim().isEmpty) {
      return <String, Object?>{};
    }""",
        """    if (text == null) {
      return <String, Object?>{};
    }""",
        "an empty or whitespace-only document holds nothing",
    ),
    # -- preferences ---------------------------------------------------------
    Mutation(
        3,
        "preferences: a wrong-typed read coerces instead of returning null",
        "lib/src/preferences.dart",
        """    if (held['type'] != type) {
      return null;
    }""",
        """    if (false) {
      return null;
    }""",
        "reading a key as the wrong type gives null",
    ),
    Mutation(
        4,
        "preferences: a string list keeps the order it was given",
        "lib/src/preferences.dart",
        "_put(key, _stringList, value.toSet().toList()..sort())",
        "_put(key, _stringList, value)",
        "a string list is stored as a set",
    ),
    Mutation(
        5,
        "preferences: reading a string list sorts it again",
        "lib/src/preferences.dart",
        "    return items;",
        "    return items..sort();",
        "reading does not sort",
    ),
    # -- the knowledge base --------------------------------------------------
    Mutation(
        6,
        "the knowledge base: a title alone matches, without the package",
        "lib/src/knowledge.dart",
        """      if (!contact.packageNames.map(_normalise).contains(wantedPackage)) {
        continue;
      }""",
        "",
        "the right title in the wrong package is not a match",
    ),
    Mutation(
        7,
        "the knowledge base: an empty title matches the first contact",
        "lib/src/knowledge.dart",
        "    if (wanted.isEmpty) {",
        "    if (false) {",
        "an empty title matches nothing",
    ),
    Mutation(
        8,
        "the knowledge base: an empty package name is not refused up front",
        "lib/src/knowledge.dart",
        "    if (wantedPackage.isEmpty) {",
        "    if (false) {",
        "an empty package name does not match a contact that has one",
    ),
    Mutation(
        9,
        "the knowledge base: the log window is reversed",
        "lib/src/knowledge.dart",
        "for (final Map<String, Object?> row in all.sublist(from)) "
        "_decodeEntry(row),",
        "for (final Map<String, Object?> row in all.sublist(from).reversed) "
        "_decodeEntry(row),",
        "history is appended oldest first",
    ),
    Mutation(
        10,
        "the knowledge base: a limit of zero returns the whole log",
        "lib/src/knowledge.dart",
        "    if (limit <= 0) {",
        "    if (false) {",
        "a limit of zero or less returns nothing",
    ),
    Mutation(
        11,
        "the knowledge base: deleting a contact keeps its history",
        "lib/src/knowledge.dart",
        "final bool hadLog = logs.remove(id) != null;",
        "final bool hadLog = false;",
        "deleting a contact takes its history with it",
    ),
    Mutation(
        12,
        "the knowledge base: a row with no id is dropped instead of refused",
        "lib/src/knowledge.dart",
        "      if (row['id'] is! String) {",
        "      if (false) {",
        "a note with no id refuses the document",
    ),
    Mutation(
        13,
        "the knowledge base: the log is read with the keyed rule",
        "lib/src/knowledge.dart",
        "static List<Map<String, Object?>> _anyRows(Object? raw) => "
        "_shape(raw, _logsKey);",
        "static List<Map<String, Object?>> _anyRows(Object? raw) => "
        "_rows(raw, _logsKey);",
        "a log line has no id, and must not be judged as if it had",
    ),
    # -- the memory store ----------------------------------------------------
    Mutation(
        14,
        "the memory store: apply writes without consent",
        "lib/src/memory.dart",
        """    if (contents[_consent] != true) {
      throw StateError('长期记忆尚未获得用户同意');
    }
    if (contents[_paused] == true) {""",
        """    if (contents[_paused] == true) {""",
        "a store nobody has consented to writes nothing",
    ),
    Mutation(
        15,
        "the memory store: a paused store still writes",
        "lib/src/memory.dart",
        "    if (contents[_paused] == true) {",
        "    if (false) {",
        "a paused store refuses writes but still reads",
    ),
    Mutation(
        16,
        "the memory store: consent needs no confirmation",
        "lib/src/memory.dart",
        "    if (!confirmed) {",
        "    if (false) {",
        "consent is required to be confirmed",
    ),
    Mutation(
        17,
        "the memory store: an empty value is stored",
        "lib/src/memory.dart",
        "    if (trimmed.isEmpty) {",
        "    if (false) {",
        "an empty value is refused",
    ),
    Mutation(
        18,
        "the memory store: the value cap is not enforced",
        "lib/src/memory.dart",
        "    if (trimmed.length > maxValueChars) {",
        "    if (false) {",
        "the value cap is upstream MAX_VALUE_CHARS",
    ),
    Mutation(
        19,
        "the memory store: the capacity bound is not enforced",
        "lib/src/memory.dart",
        "    if (existing < 0 && records.length >= maxRows) {",
        "    if (false) {",
        "the capacity bound is upstream MAX_ROWS",
    ),
    Mutation(
        20,
        "the memory store: a malformed row is dropped instead of refused",
        "lib/src/memory.dart",
        """      if (row['subjectId'] is! String ||
          row['field'] is! String ||
          row['value'] is! String) {""",
        "      if (false) {",
        "a records entry missing a field refuses the document",
    ),
    Mutation(
        21,
        "the memory store: undo reports zero and keeps the stack",
        "lib/src/memory.dart",
        "    return count;",
        "    return 0;",
        "rolls back exactly this run and reports how many",
    ),
    Mutation(
        22,
        "the memory store: undo does not restore a value it overwrote",
        "lib/src/memory.dart",
        """      if (before == null) {
        records.removeAt(at);
      } else {""",
        """      if (before == null) {
        records.removeAt(at);
      } else if (false) {""",
        "restores a value that predates the stack",
    ),
    # -- the shared payload --------------------------------------------------
    Mutation(
        23,
        "the payload: a missing key reads as an empty buffer",
        "lib/src/payload.dart",
        """      throw StateError(
        'the shared payload has no file at $key; this is a packaging fault, not '
        'a missing document',
      );""",
        "      return Uint8List(0);",
        "a missing key is a hard error, not an empty buffer",
    ),
    Mutation(
        24,
        "the payload: a missing directory reads as an empty listing",
        "lib/src/payload.dart",
        """      throw StateError(
        'the shared payload has no directory at $key; this is a packaging '
        'fault, not an empty payload',
      );""",
        "      return const <String>[];",
        "a missing directory is a hard error, not an empty list",
    ),
    Mutation(
        25,
        "the payload: the listing is handed back in the order it arrived",
        "lib/src/payload.dart",
        "    return names..sort();",
        "    return names;",
        "the listing is sorted",
    ),
    Mutation(
        26,
        "the payload: a key may walk out of the payload tree",
        "lib/src/payload.dart",
        "              segment.isEmpty || segment == '..' || "
        "segment.contains(r'\\'),",
        "              segment.isEmpty || segment.contains(r'\\'),",
        "is refused, and it is an ArgumentError",
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
    """The shared package's whole suite. Returns (exit code, output)."""
    result = subprocess.run(
        [DART, "test", "--reporter", "compact"],
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
