# Give only the bubble and the panel their own window

- Status: accepted
- Date: 2026-10-03

## Context

Both desktop ports are multi-window today. macOS opens at least four:
`overlay.py`'s `OverlayPanel`, `settings_ui.py`, `detail_ui.py` and `trend_ui.py`.
Windows is similar (`app/overlay.py` plus settings, debug and trend windows).

Flutter stable has no supported multi-window API — the windowing classes remain
`@internal`, unexported, and throw unless a feature flag that no stable channel
enables is on. The only route is a package such as `desktop_multi_window`, where
**every window is a separate `FlutterEngine` and isolate**: plugins must be
registered per engine, and state crosses by method-channel serialization.

One surface genuinely cannot be a route in another window. The bubble and the
panel float above other applications, must not take focus, remain visible while
the user works elsewhere, and are the entire reason the product exists. Everything
else — settings, detail, the K-line view, the knowledge base — is a screen the
user reads deliberately and can be a page.

## Decision

**Only the bubble and the panel are their own window. Every other surface is a
route in the main window.**

1. **The main window is the sole capability holder.** The capture loop, OCR, the
   judgement and drafting calls, credentials and payload loading live in one
   engine. It may keep running with its window hidden; closing the window is not
   the same as quitting.
2. **The panel window is a view plus a command channel.** It receives a snapshot
   and sends commands — inject, copy, request detail, toggle read-only. It holds
   only transient view state: where it was dragged to, whether it is collapsed.
3. **The read-only state is derived in the main window, not in the panel.** ADR-0002
   puts the derivation where the conversation identity is known and leaves the
   renderer with nothing to decide; on desktop that owner is the main window, the
   counterpart of `ChatCaptureService` on Android. The panel renders the state it
   is given.
4. **One snapshot contract, not one per surface.** Settings, detail, the K-line
   view and the knowledge base read the domain in-process. Only the panel crosses
   an isolate boundary, so only the panel's payload needs a serialized shape.

## Rejected alternatives

- **The panel and the detail view as separate windows.** The detail view is long
  content a user reads while looking at the chat, so a window beside the chat is
  the better shape. Rejected on cost: it adds a second engine and a second
  serialized protocol for one screen.
- **Panel, detail and trend all as windows** — closest to today's macOS layout.
  Rejected: three extra engines and the largest serialization surface, in exchange
  for preserving window behaviour no user asked for.
- **No second window at all: the panel is an overlay inside the main window.**
  Zero serialization and zero multi-window risk. Rejected because it destroys the
  product: the bubble would only exist while the main window is open and on top.
- **Give the panel its own view model** and let it subscribe to results directly.
  Least cross-isolate traffic and the most responsive drag. Rejected because state
  would then have two homes, and ADR-0002's read-only derivation — which has
  already been paid for once — is exactly the kind of derived state that drifts
  when it is computed in two places.
- **Wait for Flutter's official windowing API.** Rejected: it is experimental and
  main-channel-only, and the bubble cannot be deferred to a framework roadmap.

## Consequences

- **A visible product change on desktop:** the detail and K-line views stop being
  windows that can be dragged beside the chat. This is a deliberate trade, and the
  one thing here a user would notice.
- **The main window must be able to exist hidden**, otherwise closing it would take
  the capture loop and credentials with it while the panel is still on screen. That
  is platform-specific work on an `NSPanel`-style auxiliary window on macOS and a
  frameless always-on-top window on Windows.
- **One serialized contract exists**, so the panel's output shape is the only place
  where a field change has to be made twice. The recovery path, if that ever proves
  too costly, is to fold the panel into the main window — which is a product
  decision, not a technical one.
- **ADR-0002's guardrail keeps a single owner per port**, which is what makes it
  survivable through the migration; its known failure mode is silent simplification
  in a Dart rewrite, and one owner per port is the cheapest way to make that
  visible.

## Verified on macOS (2026-10-03, gate experiment B)

The two properties this decision depends on were unproven when it was written, and Apple
documents neither. Gate experiment B (issue #2) settled both on a real device, Flutter 3.47.6
with Impeller:

- **A real click gives the panel key focus without activating the app.** The panel became key
  on click while the workspace kept naming the other application frontmost, with the activation
  count at `0` across every sample. `NSPanel` with `.nonactivatingPanel`, `level = .floating`
  and `canBecomeMain = false` is sufficient; no focus juggling is needed.
- **A Chinese input method composes and commits inside that panel.** A live `composing` range
  ran through a pinyin sequence and a picked candidate committed as Han characters, while
  another application stayed frontmost. This is why the "compose in the main window, panel is
  read-only" fallback is not needed.

Two implementation facts carry forward, both learned from measuring rather than from reading:

- **`NSApp.isActive` cannot judge this.** For a non-activating panel it reads `true` whenever
  the panel holds key focus, whether or not the application is active. Judge on which
  application the workspace calls frontmost, and on activation *transitions* — never on a
  polled boolean.
- **Launching the app activates it once**, before any click, so activation counts must be
  differences from a baseline rather than totals, or the launch is indistinguishable from a
  click stealing focus.

Evidence and the full protocol: `.workbuddy/experiments/gate-b-macos-panel/NOTES.md`.

## Consequences for the Windows panel

The macOS shape does not transfer by itself. Windows has no `nonactivatingPanel` equivalent,
so the equivalent property has to be established for the frameless always-on-top window before
the panel may host a text field. The macOS finding is evidence that the *product* shape works,
not that the Windows implementation is settled.

## Consequences for the panel's own text field

Because the panel can host its own text field and keep the chat's focus, the copy-in-place
flow needs no separate mode: the user types into the panel while the chat keeps focus. This
is the single largest piece of user-visible behaviour that the migration would otherwise have
had to invent, and it is now known to be buildable on at least one desktop platform.
