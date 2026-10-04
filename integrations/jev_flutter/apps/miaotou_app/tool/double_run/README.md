# The Dart ↔ Python double run

**Migration instrument. Delete this directory with the ports it compares.**

It exists for one question: before a remaining Python port is deleted, is there any
fixture on which the Dart domain reaches a different conclusion than the code
that is about to be deleted? It answers that by running one fixture set through
both and comparing the conclusions, area by area.

The macOS comparisons finished before `archive/jev-mac-python-final` and were
removed with that port. The instrument now retains only the comparisons against
the frozen Windows Python port.

It is not a test suite and it is not a permanent guard. It has no place in CI:
it compares against code that is scheduled for deletion, so it can only be run
while that code still exists, and a permanent guard would have to be a guard
over nothing. What is permanent are the domain's own tests — every behaviour
compared here is pinned in `packages/miaotou_domain/test/`, and they stay.

## Running it

From the workspace root, then the application package that hosts the probes:

```sh
export PATH=/Users/raywang/dev/flutter-3.47.6/bin:$PATH   # 3.47 is the pinned SDK
cd integrations/jev_flutter/apps/miaotou_app
python3 tool/double_run/compare.py
```

That runs `probe.dart`, runs `probe.py`, pairs every fixture by id and rewrites
`report.md`. It exits non-zero when a divergence has no entry in
`known_divergences.json` — the instrument may find differences, it may not leave
them unaccounted for.

```sh
python3 tool/double_run/compare.py --self-check
```

poisons one conclusion on purpose and insists the comparator reports it. A
comparator that agreed with everything would still print a green report, so this
is the mutation the instrument is given before it is trusted.

## What is compared

| Area | Ticket | Dart | Python |
| --- | --- | --- | --- |
| `injection` | #10 | `suspectInjectionTexts` / `otherRecentTexts` / `sanitizeCandidateTexts` | `jev_windows/core/draft.py`: `_suspects` / `_her_recent` / `_sanitize` |
| `update` | #10 | `newerRelease` | `jev_windows/app/update.py`: `parse_version` |
| `csv_grid` | #8 | `writeCsvGrid` / `parseCsvGrid` | the `csv` module's round trip |

Two areas the domain owns are **not** here, and the reason is in each case that
there is nothing on the Python side to run:

* **#12, conversation identity and the read-only derivation.** Android's
  `displayLabel()` is Kotlin and there is no Python port of it; macOS and
  Windows never named a conversation. The domain's behaviour is pinned by
  `conversation_test.dart` and Android's by `ConversationRefTest.kt`, and the
  two were compared by reading, not by running.
* **#9, the memory store's save and undo.** ADR-0010 is a redesign, not a port:
  the domain drops the op-id and undoes by rewriting the previous values, while
  macOS's `MemoryBridge` replays op-ids against the upstream CLI. Running both
  would compare two deliberate designs, and the difference is the ADR, not a
  regression.

**Wording is never compared.** A refusal sentence is port-local, so only
accept/reject and the values that follow from it travel between the two sides.

## When it is deleted

With the Windows Python port in its retirement ticket (#20). Nothing else in the
repository imports this directory; deleting it cannot break a build, which is
why the check that it still runs is a person running the command above rather
than a job that would fail when the port goes.
