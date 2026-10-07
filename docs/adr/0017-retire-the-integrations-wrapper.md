# Retire the `integrations/` wrapper and name the app layer `app/`

- Status: accepted
- Date: 2026-10-05

## Context

`integrations/` was the app layer's original shape: one directory per upstream port
(`integrations/jev_android`, `integrations/jev_mac`, `integrations/jev_windows`), each
an integration of a Jev Chat assistant. The word was not decoration — ADR-0003 kept it
precisely because it carried the "upstream port" meaning, and refused the clearer word
`apps/` for that reason.

ADR-0007 collapsed the three ports into one Flutter codebase at
`integrations/jev_flutter/`, ADR-0014 replaced them one at a time, and the last one —
Android, `#24` — took `integrations/jev_android` with it. ADR-0007 predicted the shape
exactly: "`integrations/` grows by one directory before it shrinks by three." The shrink
is now complete and the consequence is fully spent, which changes the premises three
earlier documents rested on:

1. **The plural word now names a set of one.** `integrations/` holds `jev_flutter` and
   nothing else. There is no second integration, and the word's meaning — several ports
   of the same product, integrated side by side — has no referent left.
2. **`jev_` was a discriminator whose contrast set was deleted.** The prefix existed to
   tell `jev_flutter` apart from `jev_mac`, `jev_windows` and `jev_android`. With no
   siblings it distinguishes nothing; and it is the only `jev_`-prefixed directory in an
   app layer whose own convention is `miaotou_*` (`miaotou_app`, `miaotou_domain`,
   `miaotou_capabilities*`), while `GLOSSARY.md` assigns the `jev*` vocabulary to the
   upstream side and forbids the application side from using it as a brand.
3. **`documentation/` sat at the root as an app-layer exception while colliding, by
   name, with upstream's directory.** ADR-0003 named that collision as its third symptom
   and left the directory where it was.

Meanwhile four live artifacts described a layout that no longer existed, and they were
the reason this was noticed at all: `scripts/validate_layout.py` registered
`integrations` as "the three platform ports"; `README.md` still said "three app entries";
`app/README.md` titled itself "one application, three ports" and declared Android "not
promoted" although `9629f3b` had promoted it; and `.vscode/launch.json` named a Java
project `jev-android`, after a directory deleted weeks earlier. A validator that
misdescribes the layout it guards is a defect, not untidiness.

Two rejections are directly in the way and are not discarded silently. ADR-0003 rejected
renaming `integrations/` to `apps/` for two stated reasons: the change would rewrite CI,
test `sys.path` entries, packaging and docs **for readability alone**, and it would drop
the upstream-port meaning the name carried. ADR-0006 rejected moving the whole app layer
into a new directory for the same class of reason.

## Decision

**The app layer is one directory named `app/`, and the application keeps one root-level
exception.**

1. **`integrations/jev_flutter/` becomes `app/`.** The directory name now equals the
   layer name `scripts/validate_layout.py` already registers for it, so the allowlist
   changes one entry name and two reason strings and invents no fifth layer name.
2. **`documentation/` is dissolved.** Its `design/` and `screenshots/` move to
   `docs/design/` and `docs/screenshots/`, and the root entry disappears with it.
   `docs/` therefore carries two kinds of material on purpose — `adr/`, `agents/`,
   `plans/` (governance) and `design/`, `screenshots/` (app layer) — and its allowlist
   layer stays `governance`. This is the accepted cost of removing the collision ADR-0003
   named instead of merely recording it.
3. **`PRIVACY.md` stays at the root.** GitHub auto-detects it only there and the
   application hard-codes that URL in two places; ADR-0006 already rejected moving it.
4. **The internal structure does not change.** `apps/miaotou_app/` stays the single
   application and `packages/` keeps the interface package, the three capability packages
   and `miaotou_domain`. `apps/` is not a lone wrapper — it has `packages/` as a peer, and
   both are the pub-workspace vocabulary the workspace's own `pubspec.yaml` declares.
5. **Every stale statement is corrected in the same change** — the allowlist's reason
   strings, both READMEs, `GLOSSARY.md`, and the `.vscode` Java project name — because a
   rename that leaves the descriptions behind has only moved the problem.
6. **ADRs are append-only; `GLOSSARY.md` is not.** Path references in ADR-0001, 0003,
   0004, 0005, 0006, 0007, 0010 and 0015, and in the migration plan, are left exactly as
   written, with an inline superseded note on the passages this decision overtakes.
   `GLOSSARY.md` describes the present model, so its app-layer section, its Flutter
   migration heading and its boundary rules are edited in place, and the entries
   「冻结（旧端）」 and its matching boundary rule are deleted because no old port survives
   to be frozen.

## Rejected alternatives

- **Keep `integrations/jev_flutter/` and correct only the stale statements.** By far the
  cheapest option, and the one ADR-0003's precedent points at. Rejected because this
  change is not what ADR-0003 rejected: that rejection was of a rename *for readability
  alone*, and neither complaint here is readability. A plural word naming a set of one,
  and a prefix whose contrast set was deleted, are leftovers, not preferences — the
  decisive premise of the earlier rejection had expired.
- **Rename to `apps/`, as ADR-0003's rejected alternative proposed.** Plural, and it
  leaves room for a second application. Rejected because `apps/` reads as the port set
  that was just deleted, which is the reading this change exists to remove. A second
  application is a decision that needs its own ADR, not a directory that anticipated it.
- **`flutter/`.** Names the technology. Rejected: the app layer is not only Flutter — it
  also held `documentation/` until this change and will hold whatever build tooling
  precedes or follows the framework — and a directory named after a framework has to be
  renamed when the framework is.
- **`miaotou_flutter/`, or `miaotou_app/`.** Follows the `miaotou_*` convention and would
  have removed the `jev_` prefix too. Rejected: at the root, beside `goutoujunshi/` and
  `miaotoujunshi/`, a third `miaotou*` name makes the payload layer and the app layer read
  as two instances of one kind, which is what the layer vocabulary exists to prevent; and
  `README.md` already fixes `miaotoujunshi` at exactly three places (app display name,
  technical identifier prefix, own-payload directory), which a fourth would dilute.
  `miaotou_app` additionally collides with the application package of that name one level
  down.
- **Flatten `app/apps/miaotou_app/` to `app/miaotou_app/`** while removing the wrapper at
  the root. Removes the second single-child directory in one pass. Rejected as scope: it
  buys one level at the price of every build command, CI working directory and
  relative-path literal in the tree, for a directory that is not a lone wrapper.
- **Keep `documentation/` at the root and leave `docs/` governance-only.** Preserves the
  one-layer-per-root-entry property of the allowlist and touches nothing. Rejected because
  the name collision with upstream's `documentation/` is the thing being removed, and
  keeping it means a second root-level app exception justified by nothing but the word.
- **Move `PRIVACY.md` in with the rest.** Rejected again for ADR-0006's two reasons:
  GitHub detects it only at the root, and the application hard-codes that URL.

## Consequences

- **Superseded: ADR-0003's rejected alternative "rename `integrations/` to `apps/`."** Not
  overturned on its reasoning, which was sound for a repository carrying three ports on
  three stacks, but overtaken: both of its premises had expired by the time the last port
  was deleted. ADR-0003's other decisions — the payload directory, the member criterion,
  the allowlist, no git subtree, the package layout — stand, and its decision 4 was
  already superseded by ADR-0006.
- **Partly superseded: ADR-0006's rejected alternative "move the whole app layer into the
  new directory."** The app layer did move, to `app/`. That ADR's other decisions stand.
- **Superseded: ADR-0007's decision 1 (location) and its closing consequence.** The plan's
  §3 placement section is overtaken the same way; both carry inline notes.
- **The path depth drops by one level, and every numeric up-path moves with it.**
  `platform-build.yml`'s `Copy-Item "../../../../…"` becomes `../../../`; the Windows
  `CMakeLists.txt` `MIAOTOU_REPOSITORY_ROOT` probe loses one `..`; the Android
  `build.gradle.kts` `repoRoot` drops one `parentFile` link. **The macOS build phase needed
  no edit**: `sync_shared_payload.sh` walks up until a directory holds both payload trees
  rather than counting levels, and the Dart test helpers (`repo_payload.dart`,
  `payload_test.dart`) do the same. That walk is now load-bearing in a way it was not
  before, and is the reason this move was as small as it was.
- **Two build scripts hold the path as a literal** — `validate_payload_keys.py`'s
  `_WORKSPACE` and `build.gradle.kts`'s reference to that script — so a future move has to
  find them by grep rather than by compiler error. Recorded because it is the one cost
  this move adds to the next one.
  **[ADR-0027](0027-run-the-payload-assertion-on-flutters-own-dart-sdk.md) paid it once
  more:** the assertion is now `app/apps/miaotou_app/tool/validate_payload_keys.dart`, its
  interpreter is the Dart SDK Flutter already ships, and the literals moved with it — three
  of them, the added one being the macOS phase's `$SRCROOT/../tool/…`. The claim is
  unchanged: grep, not the compiler, finds them.
- **`docs/` now carries two kinds of material, and `validate_layout.py` cannot see it.**
  The allowlist registers one layer per root entry, so the mix is invisible to the gate.
  This ADR and `GLOSSARY.md`'s boundary rules are what record it; a future reader looking
  for the app layer has to read three places — `app/`, `PRIVACY.md`, `docs/design/` — not one.
- **The `jev-` vocabulary stays where it is honestly earned.** The retained Kotlin is still
  packaged `com.jev.probe.*`, the optional strategy service is still TypeSafe Jev, and the
  archive tags are still `archive/jev-<port>-<language>-final`. This change removes a
  directory name, not an attribution.
- **Not addressed: the product name is spelled two ways.** `panel_native.dart` sets the
  panel's window title to 「妙投军师」 and `panel.dart` persists placement under a
  `妙投军师` directory, while `GLOSSARY.md` fixes the display name as 「喵头军师」. Which of
  the two is wrong follows from a product decision, not from this layout change, so it is
  recorded here as a known fact rather than acted on.
