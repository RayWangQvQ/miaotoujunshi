# Reimplement only the memory-store subset the app uses

- Status: accepted
- Date: 2026-10-03

## Context

macOS's `MemoryBridge` does not implement memory; it shells out.
`integrations/jev_mac/memory_bridge.py:8` resolves
`parents[2]/goutoujunshi/scripts/memory_store.py` and runs it with
`sys.executable -B`, exchanging JSON over stdin/stdout. The upstream script is
**622 lines** of Python over sqlite, and its semantics are broader than the bridge
uses: a consent gate, a pause flag, an undo stack addressed by operation id, a
`POLICY_VERSION`, per-scope row limits for `user`/`object`/`relationship`/`event`/
`hypothesis`, five `SOURCE_TYPES` including `chatlab` and `assistant_inference`,
value and source length caps, and total row and operation caps.

ADR-0004 keeps the upstream payload byte-identical and read-only, so the script
cannot be adapted in place. ADR-0007 decision 4 makes the memory bridge
cross-platform, and Windows and Android have no Python interpreter at all — so on
those two ports the feature cannot be reached by porting, only by reimplementing
or dropping.

The bridge itself uses a small slice: `status` to read the consent and pause
state, `show` to list memories for a subject, `apply` to write one field, and
`undo` to roll back the writes made in the current run.

## Decision

**The memory store's used subset is reimplemented in Dart; the upstream script
becomes a semantic reference rather than the implementation.**

1. **Implement `status`, `show`, `apply` and `undo`, against the profile fields the
   settings UI actually edits.** No other command and no other field is in scope.
2. **Keep the safety semantics, not the taxonomy.** The consent gate, the pause
   flag, the undo stack and a capacity bound survive. The per-scope quota table and
   the unused source types do not: no port calls them, and scope is not something
   the UI distinguishes.
3. **Choose the store's own format.** Nothing constrains the Dart implementation to
   the upstream sqlite schema. ADR-0007 establishes that this product has never
   been released, so there is no installed data to read and no compatibility
   obligation to honour.
4. **Pin the retained behaviour with fixtures**, in the sense of ADR-0011. A
   deliberate divergence from upstream is recorded in this ADR rather than
   discovered by diffing.
5. **No Python runtime is bundled**, on any port.

## Rejected alternatives

- **Reimplement all 622 lines faithfully.** Would keep the two implementations
  behaviourally equivalent, including on paths nothing calls. Rejected because the
  equivalence costs the most and is worth the least: it is the largest single item
  in ADR-0007's union baseline, and it would be spent on the scope taxonomy the UI
  does not expose.
- **Keep the memory bridge macOS-only.** Zero reimplementation risk, honest about
  where Python exists. Rejected because it contradicts the union baseline: the
  macOS port would keep a capability the other two lack, which is the per-port
  divergence the migration exists to remove.
- **Bundle a Python runtime with the app.** Reuses the upstream script verbatim.
  Rejected on three counts: a second runtime in every package, substantial
  packaging and licence work, and it is not available on Android at all.
- **Continue to shell out on macOS and reimplement on the other two.** No rewrite
  on the port that works today. Rejected because one concept would then have two
  mechanisms and two places for the next contributor to look — the failure ADR-0005
  already paid for once.
- **Drop the memory feature for short-lived local context.** By far the simplest.
  Rejected as a user-visible regression that the union baseline explicitly rules
  out.
- **Wait for upstream to grow a portable implementation.** Upstream is a separate
  owner that this repository can only pull from (ADR-0004); the migration cannot be
  gated on a change it cannot make.

## Consequences

- **The upstream script stops being the single source of truth for this behaviour.**
  A change to `memory_store.py` upstream does not propagate; a fixture mismatch is
  the only signal, and there is no mechanical guard that upstream and this
  repository still agree — the same documentation-only stance as ADR-0005.
- **`check_upstream.py` is unaffected**, because the payload file itself is not
  touched. The drift check stays at zero; only the relationship between the payload
  and the code that used to invoke it changes.
- **What survives becomes this repository's own promise.** Consent gating, pausing
  and a capacity bound are now stated and enforced here, so `PRIVACY.md` has to
  describe the memory store as this product's behaviour rather than as the skill's.
- **The `apply` feedback loop that `MemoryBridge.save_profile` implements** —
  diffing the current profile against the stored one and issuing one operation per
  changed field, so that `undo` reverts exactly this run's writes — must be
  preserved. It is the part of the bridge worth porting line by line, and it is
  easy to lose when the transport stops being a subprocess.
- **macOS's subprocess coupling disappears**, including its 10-second timeout and
  its generic "check local storage permission" error, which currently hides which
  of several failures actually happened.
