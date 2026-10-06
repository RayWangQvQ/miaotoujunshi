# Fall back to the package name before the placeholder

- Status: accepted
- Date: 2026-10-06

## Context

ADR-0002 ruled that a conversation header must never print a raw package name:
a thread whose title could not be read was named after the app, and an app with
no known name fell back to a neutral placeholder 「未识别会话」. That placeholder
was the *only* thing a user saw when they opened an app this build has no adapter
for — Douyin, for example — so the header read 「未识别会话」 + 「尚未分析」 and
gave no clue which app was actually in front of them.

The package name is not actually unavailable: the accessibility service already
reads it from `rootInActiveWindow.packageName`, and the system can name almost any
package through `PackageManager.getApplicationLabel`. The placeholder existed by
design choice, not by necessity.

## Decision

An app with no resolved display name now shows its **package name** as the name,
rather than a placeholder. The full fallback order for the app half of a header
label is:

1. the whitelist alias (微信 / QQ / 飞书 / X — the apps this build has an adapter
   for);
2. the system's own label via `PackageManager.getApplicationLabel`;
3. the bare package name;
4. 「未知应用」 — only when even the package is unknown (no window in front,
   `ConversationRef.NONE`).

The placeholder word changes from 「未识别会话」 to 「未知应用」, because it now
means exactly one thing: *the application itself is unknown*, not *the
conversation was not recognised*. The two were conflated before; ADR-0002's
placeholder covered both.

The domain derivation reads `reference.packageName` to make this fallback — the
`ConversationLabel` type still carries only an `appName` (which may now *be* a
package name) and a `title`. `isIdentified` is unchanged: it still requires a
title, and it still gates fill, because writing a draft into the right thread
still needs the thread's name, not the app's.

## Consequences

- `ConversationLabel.of` falls back `appName → packageName`; the app half of a
  label is never null while a package is known.
- ADR-0002's "a raw package name is never shown" is superseded: a package name
  *is* shown when it is the only name available. The guardrail that remains is
  that the renderer never resolves the package itself — resolution stays on the
  platform side (ADR-0002 decision 2 holds).
- Android's `ChatApps.displayName` now takes a `Context` and resolves through
  `PackageManager` after the whitelist; `ConversationRef.displayLabel` takes the
  `Context` too.
- The 「未识别会话」 copy is retired and replaced by 「未知应用」.
