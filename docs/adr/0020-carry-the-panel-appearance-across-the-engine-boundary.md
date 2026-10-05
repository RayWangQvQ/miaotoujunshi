# Make the panel's opacity a setting, and carry it across the engine boundary

- Status: accepted
- Date: 2026-10-05

## Context

The floating panel's translucency is one hardcoded number. `panel_main.dart` builds the panel
engine's theme and overrides exactly one colour role:

```dart
cardTheme: baseTheme.cardTheme.copyWith(
  color: palette.surfaceRaised.withValues(alpha: 0.6),
),
```

That single override is the whole of the effect, and it is wider than it looks: every `Card` in
the panel engine reads `cardTheme.color`, and the panel has three of them — the collapsed ball
(`panel_page.dart:153`), the panel frame (`:303`) and each `CandidateCard`
(`candidate_card.dart:51`). So the inner cards are white-on-white over the frame and the panel is
already not uniformly translucent: the region between the cards shows more of the chat than the
cards themselves do. Everything else in the panel keeps its own colour — the read-only banner is
`toneCautionBackground` (`panel_page.dart:440-451`) and the frame's hairline is `palette.border`
(`theme.dart:46`) — and the override exists only in this engine, so no other window is affected.

The value is not carried by any native window. All three ports already make their window as
transparent as the platform allows and leave the compositing to the Flutter layer: Android uses
`PixelFormat.TRANSLUCENT` with `window.alpha = 1.0f` (`AndroidOverlayHost.kt:264-267`), Windows
sets the window background to `Color(0x00000000)` (`panel_native.dart:174`) and macOS sets
`isOpaque = false` with `backgroundColor = .clear` (`FloatingPanelHost.swift:232-233`). That
split is deliberate and was measured: gate experiment A applied the same value to the window and
to the layer, got the two multiplied (0.6 × 0.6 = 0.36) and the text dimmed with the background,
and fixed the constants at `PANEL_SURFACE_ALPHA` on the layer with `PANEL_WINDOW_ALPHA = 1.0`
(`.workbuddy/experiments/gate-a-android-overlay/NOTES.md`). `window.alpha` is also already
occupied: Android's `hideForCapture()` sets it to `0f` and restores it to `1f`
(`AndroidOverlayHost.kt:108-128`).

The number did not use to be hardcoded. The retired Kotlin port had a user-set `overlayOpacity`,
persisted in `Prefs` and clamped to 60..100, feeding `Color.argb(a, 255, 255, 255)` on the panel
background (`.workbuddy/reports/2026-10-03-flutter-migration-feasibility.md:227-229`), and
`docs/design/overlay-proposal.md:17` lists 透明度 among the settings the panel was to have. The
Flutter migration dropped the setting and kept the look.

Three properties of the current layout decide how it comes back:

1. **The panel is a second engine, and the protocol carries one thing.** ADR-0012 gives the panel
   its own window and its own isolate, and `protocol.dart` states the contract as "a frame goes
   down, a command comes up. Nothing else crosses". The panel also has no store to read: it is
   handed a `PanelFrame` and a callback.
2. **`FloatingPanel` carries window semantics only** — placement, visibility, hide-for-capture,
   focusable, events (ADR-0009 decision 7). Rendering, and therefore anything that describes it,
   belongs to the UI layer.
3. **`Preferences` has no number type with a fraction.** It offers `String`, `bool`, `int` and
   `List<String>` (`preferences.dart:12-38`).

macOS additionally has no path from the application layer into its panel at all:
`startPanelForCurrentPlatform` returns before it is reached (`capability_registry.dart:114-116`),
nothing in the application calls `floatingPanel.show` there, and `FloatingPanelHost` starts the
panel engine on the entrypoint name `panelMain` (`FloatingPanelHost.swift:91`), which does not
exist in this repository's Dart — `panel_main.dart` declares `main`, and no file carries a
`@pragma('vm:entry-point')`. The macOS panel is unreachable today.

## Decision

**The panel's opacity becomes a setting owned by the main window, carried to the panel as a second
down-stream on the panel protocol, applied on the Flutter layer.**

1. **The knob is the card fill alpha, not the window alpha.** `40..100`, default `80`, as a whole
   percent. The fill stays on the Flutter layer for the reasons above: a window alpha dims the text
   with the background, the retina feedback loop of gate experiment A returns if both are set, and
   `hideForCapture` owns `window.alpha` for 120 ms at a time.
2. **It crosses as its own down-stream, beside `PanelFrame`.** Not a field on `PanelFrame`:
   appearance is not a property of an analysis, and a frame only arrives when there is one, so the
   panel would have nothing to render its own surface from until the first analysis landed. Not a
   `FloatingPanel` member either: ADR-0009 gives that interface window semantics, and this value
   never reaches a window.
3. **The panel still derives nothing and still reads nothing.** The main window reads the setting
   and pushes it, exactly as it pushes frames: the panel is *fed* its appearance, it does not own it.
   ADR-0012's rule that the panel holds only transient view state survives reading this way, and that
   reading is now written down in `GLOSSARY.md`.
4. **Panel settings live in `Preferences` under a `panel.` prefix, and the per-port position stores
   retire.** `panel.opacity` is an `int` percent; `panel.placement` is one `PanelPlacement`
   (`anchor`, `dx`, `dy`) encoded as JSON in a string, so nothing is added to the `Preferences`
   contract. The three ports already share that vocabulary and already accept it on `show`, so the
   unified shape is the existing one: Android's `edge` becomes `topLeft`/`topRight` and its `y_dp`
   becomes `dy`. Windows' `panel-placement.json` and Android's native `miaotou_android_panel`
   preference file are both replaced by it. macOS never persisted one — its `lastPlacement` is
   within-session bookkeeping for `hide()`/`restore()`, which is the host putting back exactly what
   it took away, and that stays where it is.
5. **What follows the value, and what deliberately does not.** The ball, the frame and the candidate
   cards follow, because they already share the one token and the panel would otherwise change shape
   as it collapses. The read-only banner's fill and the frame's hairline do not: the banner is the
   one thing on the panel a user must be able to see, and a border that fades with the fill removes
   the only mark of where a mostly-transparent panel ends and the chat begins.
6. **macOS is wired into the application layer in the same change.** A real `panelMain` entrypoint, a
   main-window↔panel channel pair mirroring Android's, and `floatingPanel.show` called from
   `startPanelForCurrentPlatform`. Without the resize a collapsed macOS panel is a 420×620 window
   with a 56pt ball in one corner, and a transparent window still takes clicks: the chat underneath
   would stop being usable. That resize is new native code — a `setExpanded` on the host, pinning
   the window to the vertical edge it is already nearer and keeping its top edge, which is the rule
   `EdgeSnap` applies on the two desktop ports. `show(at:)` cannot carry it: a resize is not a
   placement, it arrives on the panel engine's own channel when the panel toggles rather than from
   the main window, and routing it through `show` would mean the application had to know the two
   sizes.

## Rejected alternatives

- **Put the value on the native window (`NSWindow.alphaValue`, `WindowManager.LayoutParams.alpha`,
  `SetLayeredWindowAttributes`).** Much less plumbing — one capability member, no panel protocol
  change, and it would work on all three ports at once. Rejected on the measured result: a window
  alpha dims the text along with the background, which is a different look from the one being opened
  up, and it collides with `hideForCapture`'s `0f`/`1f`, which would have to become "restore to the
  configured value" instead of "restore to one".
- **Add an `opacity` field to `PanelFrame`.** No new concept, no new channel member, and the frame
  already crosses. Rejected because it couples appearance to analysis: a panel with no analysis yet
  has no frame, the value would ride at whatever cadence analyses happen to land at, and every
  future reader of `PanelFrame` would have to decide whether `opacity` is part of the snapshot.
- **Let the panel engine read `Preferences` itself.** The most direct route and no protocol change.
  Rejected: it gives the panel a store, which is the one thing ADR-0012 and `protocol.dart` both
  spend their wording preventing, and it puts a second reader next to the main window's — the drift
  ADR-0002 decision 2 exists to stop.
- **Two controls: the fill alpha and a separate whole-window alpha.** The most expressive, and the
  honest way to offer both looks. Rejected as a first change: it doubles the surface for no request
  behind it, and the whole-window half carries every cost of the alternative above.
- **Split the fill token so only the frame and the ball are adjustable.** Fixes the compounding
  between the frame and the inner cards. Rejected because it is a visual redesign rather than the
  opening of an existing value, and it needs a new design token to express the difference.
- **Leave it hardcoded and keep the migration's 0.6.** Zero cost and verified by three ports already
  running. Rejected because the look is the product here — the panel sits over a chat the user is
  reading, and legibility depends on the chat behind it — and because the retired port's setting and
  the design document both said it was meant to be adjustable.
- **Add `double` to `Preferences` and store the two coordinates as numbers.** Type-honest. Rejected
  because a single JSON value under one key holds the same information, needs no contract change on
  three implementations, and keeps the placement a `PanelPlacement` rather than a pair of loose
  numbers.
- **Store placement per port under its own keys** (`edge` + `y_dp` on Android, `x`/`y` on desktop).
  Closest to the three existing stores. Rejected because the three ports already accept one
  vocabulary on `show`; keeping two shapes in storage would mean a reader has to know which port
  wrote a value before it can be understood.
- **Do only Android and Windows, and leave macOS out.** Smallest change, and defensible on the
  grounds that the macOS panel is not reachable at all yet. Rejected because a value that changes
  one surface on two ports and nothing on the third is a contract the third port silently fails, and
  because the macOS wiring is a mirror of Android's rather than new design.
- **Do the macOS wiring, but not the expand/collapse resize.** Keeps this change to channels and
  leaves window sizing to the ticket that owns the macOS panel. Rejected because the intermediate
  state is not shippable: collapsed macOS would be a transparent 420×620 window swallowing clicks
  meant for the chat.

## Consequences

- **The 0.6 constant disappears, and the default is not the current look.** `80` is more opaque than
  today's `60`: the panel becomes solid enough that the chat behind it stops being readable through
  it. Anyone comparing builds will see this as a visual change, and it is the intended one.
- **The panel's first paint uses the same default as the setting**, so a user on the default sees no
  flash while the main window's push is in flight. A user on a custom value may see one frame of the
  default, which is why the push belongs next to the frame push that already happens immediately
  after `show`.
- **The panel protocol now has two down-streams, and both need the same native buffering.** Android
  already holds `latestFrame` and re-sends it when the panel engine reports `panelReady`
  (`AndroidOverlayHost.kt:200-204`); the appearance needs the same treatment on every port, or a
  value pushed before the panel engine is up is lost.
- **The gate-A invariants stay green.** The panel window keeps `alpha = 1.0f`,
  `PixelFormat.TRANSLUCENT` and the rest that `panel_window_test.dart` asserts, because nothing in
  this change touches the native side of the alpha.
- **Two position stores become dead code**, and with them the only Dart-side path and the only native
  path that wrote a panel setting outside `Preferences`. Windows' `panel-placement.json` and Android's
  `miaotou_android_panel` file are not migrated: a panel the user had parked goes back to its initial
  placement once, which is a cosmetic cost paid at upgrade rather than a data loss.
- **The macOS panel becomes reachable, and that is a product change on that port.** Until now macOS
  had no panel to configure. It gets one here, which means this change delivers the macOS panel —
  entrypoint, channels, show and resize — as a side effect of wanting a slider on it.
- **The `Preferences` contract is now exercised by a JSON value.** `panel.placement` is a serialized
  string, so a malformed one has to be a reported error rather than a silent fall back to the
  defaults, in the same spirit as the capability contract's rule that unrepresentable cases throw.
- **The panel's appearance is "fed, not derived", and that phrasing is load-bearing.** ADR-0012's
  panel holds only transient view state; the appearance arrives from the main window the same way the
  frame does, and a future reader who sees a style value in the panel engine is meant to find that
  sentence in `GLOSSARY.md` rather than add a store to the panel.
