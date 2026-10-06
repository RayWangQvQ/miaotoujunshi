# Treat a contract refusal as a fact about the port, not a failure of the session

- Status: accepted
- Date: 2026-10-06

## Context

A debug launch of the macOS configuration does not start the application. It builds, prints
one exception and ends:

```
✓ Built build/macos/Build/Products/Debug/miaotou_app.app
[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled Exception: Unsupported
  operation: macOS cannot implement UiTreeReader.snapshots: the desktop ports read
  pixels, not accessibility nodes; the words come back through Ocr
#0      unsupportedOnThisPlatform (package:miaotou_capabilities/src/support.dart:21:3)
#1      MacosUiTreeReader.snapshots (package:miaotou_capabilities_macos/src/capabilities.dart:70:43)
#2      ConversationRuntime.start (package:miaotou_app/src/runtime/conversation_runtime.dart:65:55)
#3      main (package:miaotou_app/main.dart:59:17)
Failed to foreground app; open returned 1
Lost connection to device.
```

The exception is *correct*. macOS and Windows refuse `UiTreeReader` outright — ADR-0009
decision 2 says a desktop port reads pixels and recovers the words through OCR, and
`miaotou_capabilities_macos/lib/src/capabilities.dart:50` calls it what it is: a permanent
refusal rather than a not-yet. `src/support.dart:10` states the contract's intent in as many
words: 「A refusal must never be an empty buffer, an empty list or a plausible default.」

What is wrong is the caller. Three places in `ConversationRuntime` reached for the member as
though it were always there:

- `start()` subscribed to `capabilities.uiTreeReader.snapshots` unconditionally. The getter
  throws **synchronously**, so the exception left `main()` before `runApp` — the process came
  up owning no window at all, which is why the tool could not foreground it and then declared
  the device lost. A windowless process is not a crash report; it is a silence, and it is the
  only reason this took a debug session to find.
- `_analyze()` awaited `readActiveChat()` inside a `try` whose catch is `on Object`. The
  refusal was therefore filed as 「分析失败」, and no analysis could ever run on these ports —
  including an analysis of a batch the user had just reviewed and confirmed.
- `_fill()` awaited the same call with **no** `try` at all, from a command handler that runs
  it with `unawaited`. Every fill on these ports was an unhandled asynchronous exception.

The shape is not a slip in one line: it is the assumption that a member of the contract
either answers or fails, with no third possibility. ADR-0009 built the third possibility on
purpose, `CapabilityReport` already reads it correctly through `askCapability`'s ordered
catch (`support.dart:78`), and the runtime was the one caller that never learned it.

Nothing about this is a regression from ADR-0022. `git show HEAD` has the same unprotected
subscribe; the path has simply never been run on a desktop port.

## Decision

1. **A typed refusal is answered where it is asked, and answered as "this port has no node
   tree".** One private door, `_readTree()`, wraps `readActiveChat` and turns
   `UnsupportedError` into `null`. `start()`, `_analyze()` and `_fill()` all go through it,
   so the file keeps asking one question — *what is on screen* — instead of branching on the
   port at each of the three call sites.

2. **The pushed stream gets the same door, and answers `null` rather than an empty stream.**
   `_subscribeToPushedReads()` returns a nullable subscription. An empty stream is a
   live-looking thing that will never speak, which is exactly the shape the contract forbids
   an *implementation* to answer with; here the *caller* is the one deciding, and "this port
   does not push" is a fact the runtime already handles — without a pushed read, the batch in
   play is the one a capture produced.

3. **A refusal publishes no note.** The panel's empty state already says what to do. A note
   here would name a failure that did not happen, and the one thing the panel must never do
   is teach the user to distrust its own sentences.

4. **The permanent refusal and the in-flight one share a clause.** `on UnsupportedError`
   catches `UnimplementedError` with it, because the SDK declares the narrower one a subclass.
   At this call site both mean the same thing — *ask the capture path instead* — so splitting
   them would be two branches with one behaviour. Where the two genuinely differ,
   `askCapability` is the function that tells them apart, and it keeps doing it.

5. **Nothing that is not a typed refusal is caught.** A reader that is broken rather than
   refusing still throws: `start()` reports it as 「当前没有可分析的会话」 and `_analyze()`
   reports it as 「分析失败」. Swallowing a defect into the same `null` would make a crash and
   a desktop port indistinguishable, which is the failure mode this ADR exists to prevent,
   one level up.

6. **`_fill()` declines rather than guesses.** With no tree to re-read, the null takes the
   existing 「会话已变化」 branch and the reply is not filled. Filling into a conversation
   nobody verified is worse than not filling.

7. **The capture path is the way in on these ports, and it is already built.** ADR-0018's
   manual whole-frame capture is the same road the user takes for an application the adapter
   registry does not know — one reason further along — and ADR-0022's review surface is what
   makes it lead anywhere.

## Rejected alternatives

- **Make `MacosUiTreeReader.snapshots` return `const Stream.empty()`.** The shortest possible
  fix and forbidden by the contract: `src/support.dart` names an empty buffer, an empty list
  and a plausible default as the three shapes a silent fallback takes. A refusal exists so a
  caller *can* tell, and neutering it at the implementation moves the lie instead of removing
  it.

- **Make the tree reader nullable in `CapabilitySet`.** Then "this port has no node tree" is
  a field nobody fills rather than an answer the contract carries, `CapabilityReport` loses
  the two rows it currently shows for what macOS and Windows refuse, and the ports that
  *do* have a reader get no reason to say anything about it.

- **Catch everything in `main()` so the window always appears.** It would have made this
  session end differently and worse: an application that starts, shows its UI and does
  nothing, with the reason printed once in a console nobody reads. A launch failure that is
  loud is worth more than one that is quiet.

- **Let `_fill()` fall back to `_latest` for the "has the screen changed" check.** It would
  let filling appear to work on these ports. `_latest` is what we last read, not what is on
  screen now, so the check would answer "unchanged" for a conversation the user has since
  moved on — and the reply would be written into the wrong conversation.

## Consequences

- **The macOS configuration starts.** Verified by running it: no exception, the session stays
  up, and the process owns two windows — the main one and the panel's ball. Windows takes the
  same path and is expected to be fixed by the same change; it has not been run here.
- **Android is untouched.** Its reader answers, so none of the new branches is taken; the
  device run of the ADR-0022 flow is unaffected.
- **On macOS and Windows the only way in is a capture**, and therefore ADR-0022's review
  surface is a required step rather than an escape hatch. That is the intended shape for a
  port with no node tree, and it means the two ADRs are load-bearing for each other on those
  ports.
- **Filling a reply is not available on these ports**, and the panel says 「会话已变化」 when
  it declines — a sentence that is true of the check and not of the situation. A note that
  names the real reason (「这个平台读不到会话，填不进去」) is owed, and is not built here.
- **`main()` still has no safety net.** Any other exception out of `start()` or
  `startPanelForCurrentPlatform` still produces a process with no window. Two of the ways
  that used to happen are now handled explicitly; the general case is deliberately left loud.
