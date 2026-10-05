# Ask for screen-recording permission from the app and accept the re-prompt

- Status: accepted
- Date: 2026-10-05

## Context

The migration plan (§13, item 3) and the tracker spec both left one question open:
macOS re-asks for screen-recording permission roughly monthly, and an application
cannot answer the prompt on the user's behalf. The candidate answers were the
system picker (`SCContentSharingPicker`), a managed-device profile, an entitlement
request to Apple, or simply accepting the prompt.

Two facts about the promoted macOS port make the question concrete rather than
theoretical:

- **Capture is ScreenCaptureKit**, because `CGWindowListCreateImage` was obsoleted
  in macOS 15 and because a window filter is the only way to photograph a window
  that something is standing in front of — and the panel is always standing in
  front of the chat.
- **A missing grant is indistinguishable from a missing window.** Without Screen
  Recording the system blanks every window's title, so "no target found" is what a
  denied permission looks like from the outside. Left unstated, the user sees a
  panel that does nothing and has no way to guess why.

The implementation already answers both halves: `ChatWindowCapture.screenRecordingGranted()`
preflights before the window search and throws `CaptureError.screenRecordingDenied`
rather than returning an empty result, and `requestPermissions` in the plugin asks
the system for Screen Recording and Accessibility and reports both back as values.
This ADR records that the open item is settled that way, so a reader does not have
to infer the decision from two Swift methods.

## Decision

**The port accepts the re-prompt and asks for the permission from inside the app;
it does not attempt to make the prompt go away.**

1. **Accept the re-prompt.** A monthly re-ask is the system's behaviour and no
   application-side mechanism removes it. The product cost is one dialog; the cost
   of the alternatives is a mechanism the repository would have to maintain for as
   long as macOS keeps changing.
2. **Ask, do not infer.** A permission request is issued by the app
   (`CGRequestScreenCaptureAccess` / the Accessibility equivalent) through the
   `requestPermissions` channel method, which reports the granted flags back.
3. **A missing grant is a stated failure, never an empty result.** The preflight
   runs before the window search and produces a coded error. This is ADR-0009's
   rule applied to permissions: a port that cannot provide a capability throws
   rather than degrading into a null.

## Rejected alternatives

- **`SCContentSharingPicker`, the system picker.** Presents a picker UI the user
  has to operate on every start, which is a worse dialog than the permission
  prompt, and it selects *content to share* — display, window, application — which
  re-introduces a target choice the port deliberately holds across frames instead.
- **A managed-device (MDM) profile.** Removes the prompt for managed machines and
  does nothing for anyone else; this product ships to individuals.
- **An entitlement request to Apple.** Would only ever apply to a future build,
  has an unknown lead time, and cannot be the answer for the port that is already
  accepted. Revisit only if the re-prompt interval shortens materially.

## Consequences

- **The macOS port carries a permission affordance in its UI**, and the grant state
  is read rather than assumed. A user who has not granted it is told, instead of
  watching a panel that silently produces nothing.
- **Denial reaches the caller as a value with a code**, so the UI can say what to
  do — the same shape `CaptureOutcome` uses for a failed capture.
- **The monthly re-ask remains user-visible.** This ADR accepts it; it does not
  claim to have solved it.
