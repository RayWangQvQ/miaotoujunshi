# Conversation identity is visible, and cross-conversation is read-only

- Status: superseded by [0026](./0026-fallback-to-the-package-name.md)
- Date: 2026-10-02

## Context

The floating-ball panel mixes up two facts that used to be indistinguishable:

- the judgment and candidate replies on the panel belong to one conversation
  (**the analyzed conversation**);
- the window the user is looking at right now may be a different one
  (**the live conversation**).

Android's existing fill guard was defence in depth only: before actually writing,
`fillInput` re-reads the node tree and requires `fresh.title == snapshot.title`
**and** `fresh.signature() == snapshot.signature()`
(`ChatCaptureService.verifiedInput`). That is enough to prevent filling the
**wrong** box, but it does nothing for what the user sees:

1. The panel header was only 「喵头军师」 + gear + close — no conversation label
   at all, so the user had no way to tell who the candidates were for.
2. `OverlayController.showIdle(title)` accepted `title` and never used it; when
   `lastJudgment` was non-null with non-empty content it was a no-op. So after
   switching to any non-chat app the panel kept showing the previous
   conversation's candidates, looking like a result for the current chat.
3. There was no "visible but read-only" middle state: a conversation outside the
   whitelist was simply `hide()`-en, and a non-chat window got a panel whose
   meaning was anyone's guess.

Windows (the follow/browse pair in `overlay.py`) and macOS (conversation identity
binding) already have equivalent protection. Android — the most feature-complete
port — was the one missing it.

## Decision

**1. The panel must show the analyzed conversation, and explicitly drop to
read-only when it differs from the live one.**

A second, smaller line goes in the header: `app name · conversation title` plus a
status word (`尚未分析` / `正在看` / `浏览中 · 只读`). A missing title falls back to
「未识别会话」; a **raw package name is never shown**.

**2. The read-only verdict belongs to `ChatCaptureService`;
`OverlayController` stays a pure renderer.**

The service already holds `currentSnapshot`, `activePkg`, `foregroundPkg` and
`snapshotIsCurrent` — it is the single source of truth for "which conversation is
the user looking at". The view only receives two facts — `bindConversation`
(whose analysis this is) and `setLiveConversation` (who the user is looking at
now) — and derives `readOnly = analyzed conversation != live conversation` itself.

Rejected alternative: let the view read `rootInActiveWindow` on its own. That
leaks accessibility-capture logic into the render layer and lets the read-only
verdict drift out of sync with the service's dedupe, debounce and conversation
tokens.

**3. Read-only revokes "Fill" only — never "Copy" or "Details".**

The candidates are still useful, so the panel keeps the candidate cards and the
header label and only drops the solid 「填入」, explaining why in a yellow banner
at the top. The bottom 「重新分析」 becomes 「分析当前会话」: `onManualAnalyze`
reuses `currentSnapshot`, which by definition belongs to another conversation
while read-only, so the old button silently did nothing when tapped.

## Consequences

- `OverlayController.showIdle` takes `ConversationRef?` instead of `String?`, and
  all five call sites go through `refOf(pkg, title)`. The view can no longer be
  handed half an identity.
- Read-only is a **derived** state: never persisted, never in `Prefs`. There is no
  switch to turn it off and no place to pin it. That is deliberate — a remembered
  "ignore" toggle eventually brings the mis-fill back.
- `render` is split into `render` (expands) and `renderContent` (does not). The
  read-only flip happens while the user is inside another app, where popping the
  panel open would be hijacking, so `setLiveConversation` calls `renderContent`
  only.
- Cost: the three ports are still not unified. Windows/macOS have protection with
  similar semantics but different names and implementations; unifying them is
  left to a later round.
- **Not verified on a physical Android device.** This repo's QQ / X / Feishu
  adapters are themselves marked "needs on-device verification"; this change only
  guarantees that it compiles, that the unit tests pass and that the logic was
  walked through. On-device behaviour needs separate acceptance.
