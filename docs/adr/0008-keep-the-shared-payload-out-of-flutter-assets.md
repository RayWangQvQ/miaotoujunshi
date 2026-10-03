# Keep the shared payload out of Flutter assets

- Status: accepted
- Date: 2026-10-03

## Context

ADR-0005 and ADR-0006 established what the shared payload is and how it reaches a
running port: `miaotoujunshi/` and `goutoujunshi/SKILL.md` are read from disk at
runtime, each port's packaging names the **directory** rather than its children,
and a file added to the payload must be picked up with **zero change** to any
build script. A port that cannot read a payload file fails hard rather than
falling back to an inlined copy.

The obvious way to express that in Flutter is an `assets:` entry. It does not work.
Flutter's asset documentation states that a directory entry includes only the
files directly in that directory — "if you want to add files in a subfolder, you
must create an entry for each directory". So `assets: - miaotoujunshi/` would
**not** include `miaotoujunshi/references/data/*.json`; adding a payload file
would require editing `pubspec.yaml`. That is precisely the failure mode ADR-0005
and ADR-0006 were written to remove.

Android's current zero-change behaviour is not evidence to the contrary: it works
because the Android Gradle Plugin treats an assets source directory as a physical
directory and packages everything under it, including subdirectories. Flutter's
asset declaration has no such semantics.

## Decision

**The shared payload does not go through Flutter assets. Each platform's build
copies the payload tree whole into its bundle, and Dart reads it through a
`SharedPayload` interface implemented per platform.**

1. **One Dart interface, one implementation per platform**, in the capability
   packages alongside the other platform capabilities:
   ```dart
   abstract interface class SharedPayload {
     /// Key = repository-root-relative path, the same convention payload-map.json
     /// already uses.
     Future<Uint8List> read(String repoRelativePath);
     Future<List<String>> list(String repoRelativeDir);
   }
   ```
2. **Each platform keeps the mechanism it already has.** Android keeps its
   existing Gradle copy task (`Sync`, not `Copy`) plus recursive AGP packaging, and
   answers the interface through the `AssetManager`; Windows reads the real files
   beside the executable; macOS reads the real files under
   `Contents/Resources/`. None of the three is replaced by a Flutter mechanism.
3. **Keys stay repository-root relative.** The payload's paths inside a built
   artifact continue to mirror the paths in the repository, so
   `payload-map.json` remains the single source for scene-to-file selection and
   needs no rewrite.
4. **A missing file is a hard error.** The interface throws; no implementation
   returns an empty buffer, a default, or an inlined copy.
5. **`list()` is trustworthy because the tree is copied whole.** It exists so a
   caller can enumerate a payload directory without a hard-coded member list —
   the property that makes zero-change additions observable at runtime.

## Rejected alternatives

- **Flutter assets with a build-time generated `pubspec.yaml`.** A script syncs
  the payload into an asset directory and writes the asset entries, with CI
  asserting that regenerating leaves `git diff` empty. It preserves zero-change
  additions, but it turns `pubspec.yaml` into a half-generated artifact that a
  contributor must know not to hand-edit.
- **Build the whole payload into a single `shared_payload.bundle` and declare only
  that file.** Zero-change additions hold, because the file is one opaque blob.
  Rejected: it adds a pack/unpack layer, and the built artifact stops being
  diffable — the exact property that made ADR-0006's packaging rule auditable.
- **Declare every payload subdirectory explicitly in `pubspec.yaml`.** Works
  today, breaks the invariant: the next payload subdirectory is forgotten in the
  Flutter port only, and nothing catches it until a user opens a screen.
- **Let each platform's capability package read the payload from wherever it likes
  without a shared interface.** Fewer types, but then the domain layer cannot be
  tested against a payload at all without a platform, and `dart test` — the
  cheapest part of the new test story — is lost.
- **Ship the payload only where a port names a scene** (the macOS-only scene
  selector). Superseded by ADR-0007's union baseline: every port now has the
  scene-dependent content.

## Consequences

- **`pubspec.yaml` cannot be inspected to learn where the shared files come from.**
  A contributor looking for the payload wiring will find nothing in the Flutter
  project; this ADR and each platform's build script are the answer.
- **The packaging guard must be rebuilt.** `tests/test_jev_mac.py`'s
  `test_packaged_mac_tree_contains_every_runtime_file` currently asserts that
  `scripts/package_mac.py`'s allowlist matches the files the runtime reads. Its
  replacement asserts that **every key ever requested from `SharedPayload` exists
  in the packaged tree**, otherwise the failure mode degrades from "the package
  step fails" to "the user presses a button and nothing happens".
- **ADR-0005's and ADR-0006's packaging decisions stand unchanged** for the frozen
  ports; this ADR extends them to the Flutter port rather than superseding them.
- **The Android copy task survives the migration untouched**, which is the one
  place where a legacy mechanism is reused verbatim rather than reimplemented.
- macOS remains the only port that reads the scene payload and
  `payload-map.json` today; the union baseline means the other two gain that
  wiring, and this interface is what they will read it through.
