# Carry the two Android permissions in the contract, read them, and open their system pages

- Status: accepted
- Date: 2026-10-06

## Context

The retired Kotlin port had a setup screen and the Flutter port has none of it. `MainActivity.kt`
in `integrations/jev_android/` built a readiness card plus a 权限设置 section of three cards, each
stating its real state and carrying a `去开启` button that launched a system page —
`ACTION_ACCESSIBILITY_SETTINGS` for 无障碍权限, `ACTION_MANAGE_OVERLAY_PERMISSION` with the package
URI for 悬浮窗权限, `ACTION_APPLICATION_DETAILS_SETTINGS` for 自启动 + 省电无限制 — and it rebuilt
the whole screen from `onResume` (`:61-66`) so a user coming back from a system page saw the state
change. All of it was deleted with the port in `9629f3b` (feat(android): promote Flutter
implementation (#24)), and nothing replaced it.

What the Flutter port has instead is two half-wired paths and one dead one:

- **Accessibility is reported only after it has already cost the user a failure.** Nothing reads its
  state. `MiaotouAndroidPlugin.withCaptureService` throws `accessibility_service_unavailable` when
  the live service reference is null (`MiaotouAndroidPlugin.kt:179-193`), and that one code is mapped
  to a sentence the user can act on (`conversation_runtime.dart:249-256`, `copy.dart:364-365`).
  That mapping exists because ADR-0018's first device run was reported as "没有识别出聊天消息" while
  48 lines had come back — the panel could not say *which* thing was off.
- **The overlay permission is requested implicitly and its failure is unhandled.** `show()` checks
  `Settings.canDrawOverlays` and, when it is missing, launches the system page itself and retries on
  the result (`MiaotouAndroidPlugin.kt:219-252`, `:254-279`). It raises four codes —
  `overlay_permission_unavailable` (`:229`), `overlay_permission_pending` (`:237`),
  `overlay_permission_denied` (`:262`), `android_panel_show_failed` (`:273`) — and no Dart file
  catches any of them, so a user who declines is dropped back into the app with no explanation and a
  panel that never appears.
- **macOS has a permission affordance it was already promised.** ADR-0016's consequences say "the
  macOS port carries a permission affordance in its UI, and the grant state is read rather than
  assumed", and `requestPermissions` is implemented and reports both grants back
  (`MiaotouMacosPlugin.swift:90-102`). It has no Dart caller.

Two facts about the Android side decide the shape rather than the plumbing:

1. **Ticked is not bound, and the difference is the failure users actually hit.** 无障碍 has two
   separate facts behind it: `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` says the user moved
   the switch, while the live service reference says the platform has actually bound the service.
   Ticked-but-not-bound is a real, recurring state — this device carries three *retired* apps whose
   services are on, which looks exactly like a configured device while the build under test has
   nothing — and it is the state ADR-0018's device run was in when `accessibility_service_unavailable`
   came back. A boolean cannot express it, so the UI would end up saying "未开启" to a user who has
   just switched the service on and can see it on their screen.
2. **Opening a system page reports nothing back.** `ACTION_ACCESSIBILITY_SETTINGS` has no result: the
   user may enable, enable and return, or leaf through and come back unchanged, and the app learns
   nothing from the launch. That is not the same operation as ADR-0016's macOS
   `CGRequestScreenCaptureAccess`, which asks and returns flags.

ADR-0009 makes the platform layer the only place the ports may differ and states that support is
declared rather than implied, so a permission surface has to be answered for by all three ports even
though only one of them has permissions of this kind.

## Decision

**`Permissions` becomes the contract's eleventh interface, and it can read state and open system
pages — it cannot ask.**

1. **Eleventh interface, in the platform group.** `Permissions` joins `ScreenCapture`,
   `UiTreeReader`, `Ocr`, `TextInject` and `FloatingPanel` in `miaotou_capabilities`, with the
   implementations in `miaotou_capabilities_<platform>`. ADR-0009's "ten interfaces" becomes eleven,
   and the reason to add it rather than hang it off `FloatingPanel` is that only one of the two
   permissions has anything to do with a window.
2. **Two methods, and deliberately not `request`.** `read()` returns the state of the permissions
   the port has, and `openSettings(kind)` opens the system page for one of them. There is no
   `request(kind)` returning a result: by fact 2 above, Android's page reports nothing back, so a
   `request` would be a promise the platform cannot keep and would contradict ADR-0016 decision 2's
   wording.
3. **The state is three-valued: `off`, `inactive`, `ready`.** `inactive` means granted in the system
   but not currently in effect, which is fact 1 above. The words describe whether the capability
   works, not what Android calls the mechanism. The overlay permission only ever answers `off` or
   `ready`, because `Settings.canDrawOverlays` has no middle state.
4. **`PermissionKind` carries the two readable permissions only.** `accessibility` and `overlay`.
   自启动 + 省电无限制 is not one of them: it is not readable and, for this version, not jumpable
   either (see the deferred alternative below), so it does not enter the contract at all.
5. **The Android component name never leaves Kotlin.** `read()` answers `accessibility` by reading
   `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` *and* the live service reference, and returns
   `inactive` when only the first is true. Dart receives an enum and never learns a package or class
   name, which is ADR-0009's rule that a port detail does not cross the boundary.
6. **The two desktop ports refuse, explicitly.** macOS and Windows throw `UnsupportedError` for both
   members, per ADR-0009 decision 2. **This does not pay ADR-0016's macOS debt**: `requestPermissions`
   still has no Dart caller, and wiring the macOS affordance — which is about screen recording and
   the Accessibility API, not about the two Android permissions — remains open and is now written
   down rather than assumed.
7. **The surface is the top of `settings_page.dart`, as three rows.** 无障碍 and 悬浮窗 each show
   their state and a `去开启` button that calls `openSettings`; 自启动 + 省电无限制 is a third row
   with no state and no button, carrying the instruction in prose alone ("小米/HyperOS 必做，否则
   服务被冻结、读不到消息"). The section sits above the model, policy and panel settings because it
   is a precondition for the app working at all, not a preference. There is no readiness summary card
   and the API key is not one of its rows: the key already lives in the model settings, and repeating
   it would put "is it configured" in two places.
8. **The capture failure becomes actionable.** The `runtimeCaptureServiceOff` sentence gains a
   control that calls `openSettings(accessibility)` directly. The failure is the moment the entry
   point is most needed, and ADR-0018's device run is the evidence that a sentence alone left the
   user stuck.
9. **The state is re-read when the section is built and when the app returns to the foreground.**
   The retired port rebuilt in `onResume` for this reason; a user who leaves for a system page and
   comes back is the whole point of the surface, and a value that changes only on a manual refresh
   would be stale exactly when it matters.
10. **The implicit overlay jump in `show()` stays, and its codes get handlers.** The row is an
    explicit second way to the same page; the automatic one is what makes the panel appear without a
    detour for a user who never opens settings. What changes is that the four `overlay_permission_*`
    codes stop being dangling: they reach the panel as text the user can act on, in the shape
    `runtimeCaptureRefused` already uses for a refusal with a reason (`copy.dart:363`).
11. **The diagnostics page does not show live permission state.** `capability_report.dart` answers
    what a port has implemented; the new member appears there automatically through
    `CapabilitySet.describe()`. Whether *this machine* currently allows something is a different
    question and stays in settings, which keeps ADR-0009's "support is declared, never implied" true
    of the page that exists to state it.

## Rejected alternatives

- **A vendor table that opens each ROM's own autostart page.** A `包名 → ComponentName` table in
  Kotlin (小米/红米, 华为/荣耀, OPPO/一加/realme, vivo/iQOO, 魅族, 三星), each entry tried with
  `startActivity` under `runCatching` and falling back to the generic application-details page, with
  the table extracted as a pure function so it could carry JVM unit tests. **Deferred, not rejected
  on merit:** it is the only way the 自启动 row could ever be a real jump rather than a sentence, but
  it is a table nobody can validate on more than one device, it rots as vendors rename their
  activities, and it is a larger change than the problem it solves for this version. The row keeps
  its text; if the instruction alone proves insufficient on real devices, this is the alternative to
  come back to.
- **A single `request(kind)` method.** Smaller contract, one method instead of two. Rejected because
  it packages "we will take you to a system page" as "we are asking for this", and on Android the
  page returns nothing — the shape would misdescribe the mechanism the way ADR-0016's wording
  deliberately avoids.
- **`(granted, effective)` as a pair of booleans instead of the enum.** Same expressive power and no
  vocabulary to agree on. Rejected because it pushes the composition of the two facts onto every
  caller, and the one question actually asked of this interface is "does it work", which is a
  decision, not a pair.
- **Hanging the members off `FloatingPanel`.** One less interface, and the overlay permission is at
  least window-adjacent. Rejected because the accessibility permission is not, and ADR-0009 decision 7
  gives that interface window semantics rather than a mixed bag.
- **An Android-only channel with a `Platform.isAndroid` branch in the application layer.**
  `capability_registry.dart:133-150` already branches on the platform for the panel, so the precedent
  exists. Rejected because it leaks a platform difference into the UI layer, which is the thing
  ADR-0009 exists to prevent, and because it would make macOS and Windows silently lack a member
  rather than state that they do.
- **Merging the 自启动 instruction into the 无障碍 row's description.** One row fewer, and it is the
  accessibility service that gets frozen. Rejected because it makes a one-line description carry two
  instructions, and the user's reason to act on it (a service that gets killed) disappears into a
  subordinate clause.
- **A readiness summary card that also counts the API key**, restoring the retired port's shape
  exactly. Rejected because the section is a permission section: it would duplicate the key's state
  from the model settings and re-introduce "尚未就绪" as a concept the app has to keep honest
  everywhere.
- **Hard-coding the accessibility component name in Dart.** Simplest comparison, and the retired port
  did exactly that (`"$packageName/com.google.android.accessibility.selecttospeak.SelectToSpeakService"`).
  Rejected because it pins the UI to an implementation package's class name, and the retired port's
  version was already wrong about its own package.
- **Removing the implicit overlay jump from `show()`** so the row is the only way to that page.
  Predictable, and no one gets thrown into a system page unannounced. Rejected because the first run
  would then cost two trips through settings for a user who never asked to configure anything.

## Consequences

- **The contract is eleven interfaces.** ADR-0009's decision text is amended in place, and every
  implementation package plus the in-memory set and the support-declaration test answer for the new
  member or fail to compile.
- **Ticked-but-not-bound gets a name and a display.** The state ADR-0018's device run was in is now
  visible before a capture fails, which is the difference between "it doesn't work" and "switch the
  service on".
- **The four `overlay_permission_*` codes stop being dangling.** A declined overlay permission
  currently ends in a panel that never appears; from here it ends in a sentence with a way out.
- **ADR-0016's macOS affordance is still owed, and this ADR says so.** A reader who finds
  `requestPermissions` without a caller will find the reason it is still without one.
- **The 自启动 row asserts nothing and will never reflect whether the user acted.** It is a
  paragraph, not a permission, and the vendor table that would change that is recorded above as the
  deferred alternative rather than quietly dropped.
- **Two states of the same permission are now distinguishable in the UI, so the copy has to keep
  them apart.** `off` and `inactive` need different sentences, and the difference is not visible in
  the system page the user was just looking at.
