import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'advice.dart';
import 'conversation.dart';
import 'conversation_note.dart';
import 'manual_recognition.dart';
import 'model_settings.dart';
import 'snapshot.dart';

/// What the panel is doing, and why — the whole of the runtime's judgement.
///
/// One value in, one list of effects out, and nothing awaited in between. The
/// engine never reads a clock, touches a screen or waits for a model; every one
/// of those is an [ConversationEffect] it asks for and a [ConversationEvent] it
/// is told about. That is what makes the runtime's decisions testable at all:
/// the transitions are plain synchronous calls, and the whole thing runs under
/// `dart test` with no device.
///
/// **What is here and what is not.** ADR-0009 decision 3 splits the runtime in
/// two: the platform owns *when* — a rate limit, a backoff, a watchdog, hiding
/// the panel for a capture — and the domain owns *what*, which is what the panel
/// shows and what the user is allowed to do about it. Nothing in this file
/// paces anything, and none of the implementation's own timing moved: what moved
/// is the set of decisions that were living beside that timing. "识别中" and
/// "分析中" are on the panel because this file says so; "should a second request
/// be refused" is a decision; and "does this refusal carry a way out" is one.
/// [derivePanel] in `conversation.dart` already occupies exactly this ground.
///
/// **Where the words are.** Not here. Every note is a [NoteCode] or a sentence
/// somebody else wrote, and the application is the side that turns a code into
/// copy. This package holds no string a screen shows, which is the same rule
/// that keeps [ModelSettings.goal]'s default in the application.
///
/// **The state is the view, and nothing is published.** There is no
/// `PublishFrame` effect, because there would be one after every event: the
/// caller reads [state] once the effects have run and translates it itself. A
/// state that had to be *told* to publish is a state with two ways to be stale.
final class ConversationEngine {
  ConversationEngine({
    this.requiresConfiguredModels = true,
    ConversationState? state,
  }) : state = state ?? ConversationState();

  /// Whether a round cannot run until the model is configured.
  ///
  /// True wherever the round is a real model call: an unconfigured application
  /// must say 「请先配置模型」 rather than reach a wire it has no address for.
  /// False for a caller that substitutes its own round runner, because then
  /// there is no wire to configure and refusing would be about a model nobody
  /// is going to call.
  final bool requiresConfiguredModels;

  /// Everything the panel is showing, and everything in flight.
  ///
  /// Mutable, and written only here. The caller reads it once the effects of an
  /// [apply] have run — see the class comment for why it is not copied out.
  final ConversationState state;

  /// Advances the machine by one step and answers with what to do about it.
  ///
  /// One step, not a loop: an event never produces another event, and the
  /// caller is what turns an effect's result into the next one. That is what
  /// keeps every transition reachable from a test with no concurrency, and it
  /// is why the effects are a list rather than a callback.
  List<ConversationEffect> apply(ConversationEvent event) {
    if (state.disposed && event is! EngineDisposed) {
      return const <ConversationEffect>[];
    }
    return switch (event) {
      EngineDisposed() => _onDisposed(),
      Started() => _onStarted(),
      TreeAnswered() => _onTreeAnswered(event),
      SnapshotPushed() => _acceptSnapshot(event.snapshot),
      SnapshotStreamFailed() => _onSnapshotStreamFailed(),
      CommandReceived() => _onCommand(event),
      FrameCaptured() => _onFrameCaptured(event),
      CaptureRefused() => _onCaptureRefused(event),
      CaptureThrew() => _onCaptureThrew(event),
      RecognitionFailed() => _onRecognitionFailed(),
      LinesRecognised() => _onLinesRecognised(event),
      AutoAnalyseRead() => _onAutoAnalyseRead(event),
      RoundSettingsRead() => _onRoundSettingsRead(event),
      AnalysisSucceeded() => _onAnalysisSucceeded(event),
      AnalysisRefused() => _onAnalysisRefused(event),
      AnalysisFailed() => _onAnalysisFailed(),
      FillTargetResolved() => _onFillTargetResolved(event),
      InjectionResolved() => _onInjectionResolved(event),
    };
  }

  // ---------------------------------------------------------------- the start

  List<ConversationEffect> _onStarted() => const <ConversationEffect>[
    ReadTree(TreeReadPurpose.start),
  ];

  List<ConversationEffect> _onTreeAnswered(TreeAnswered event) =>
      switch (event.purpose) {
        TreeReadPurpose.start => _onStartTreeAnswered(event),
        TreeReadPurpose.analysis => _onAnalysisTreeAnswered(event),
        TreeReadPurpose.fill => _onFillTreeAnswered(event),
      };

  /// The first read of the session.
  ///
  /// A reader that threw is answered with 「没有对话」 and deliberately not with
  /// a failure of its own: the two cases a start can be in are "there is
  /// nothing in front of the user" and "this port cannot answer at all", and
  /// every other message about it would be a second thing to read before the
  /// user can do the one thing there is to do — capture the screen.
  ///
  /// A read that *answered* null publishes nothing at all, which is the port
  /// that refuses the node tree (ADR-0009 decision 2, [UiTreeReader]): a
  /// refusal is a statement about the platform rather than a failure, and the
  /// empty state already says what to do.
  List<ConversationEffect> _onStartTreeAnswered(TreeAnswered event) {
    if (event.threw) {
      _publish(note: const CopyNote(NoteCode.noConversation));
      return const <ConversationEffect>[];
    }
    final ChatUiSnapshot? initial = event.snapshot;
    return initial == null
        ? const <ConversationEffect>[]
        : _acceptSnapshot(initial);
  }

  List<ConversationEffect> _onSnapshotStreamFailed() {
    _publish(note: const CopyNote(NoteCode.noConversation));
    return const <ConversationEffect>[];
  }

  // ------------------------------------------------------ the panel speaking

  List<ConversationEffect> _onCommand(CommandReceived event) {
    switch (event.kind) {
      case ConversationCommandKind.analyseCurrent:
      case ConversationCommandKind.reanalyse:
        return _beginRound(manual: true);
      case ConversationCommandKind.recogniseOnce:
        return _onRecogniseOnce();
      case ConversationCommandKind.copy:
        return _onCopy(event.text);
      case ConversationCommandKind.fill:
        return _onFill(event.text);
      case ConversationCommandKind.details:
      case ConversationCommandKind.close:
        return const <ConversationEffect>[];
      case ConversationCommandKind.openPermissionSettings:
        if (event.permission case final PermissionKind kind) {
          return <ConversationEffect>[OpenPermissionSettings(kind)];
        }
        return const <ConversationEffect>[];
      case ConversationCommandKind.openReview:
        return _onOpenReview();
      case ConversationCommandKind.confirmTranscript:
        return _onConfirmTranscript(
          event.lines ?? const <ChatLine>[],
          title: event.title,
          appName: event.appName,
        );
      case ConversationCommandKind.cancelReview:
        return _onCancelReview();
    }
  }

  /// The batch on the panel, as the panel shows a line.
  ///
  /// The rectangle a captured line may carry stays on the other side of this:
  /// the panel has nowhere to point at, and the frame it is fed carries speaker
  /// and words and nothing else.
  List<ChatLine> _transcriptOf(List<ChatLine> lines) => <ChatLine>[
    for (final ChatLine line in lines)
      ChatLine(speaker: line.speaker, text: line.text),
  ];

  /// Puts the batch on the panel into the review state (ADR-0022).
  ///
  /// The panel asks for a state and not for data: the lines it has to edit are
  /// the ones it is already being shown, and the engine is the side that holds
  /// the batch. So this republishes with `reviewing` set and leaves the
  /// transcript where it is. Both doors arrive here — the standing 「核对」
  /// button and the 「去核对」 of a refusal — because they ask for the same
  /// thing and the engine already knows which batch is on the panel.
  List<ConversationEffect> _onOpenReview() {
    final PanelBatch? batch = state.latest;
    if (batch == null || batch.snapshot.lines.isEmpty) {
      _publish(note: const CopyNote(NoteCode.noConversation));
      return const <ConversationEffect>[];
    }
    _publish(
      analysed: batch.snapshot.conversation,
      live: batch.snapshot.conversation,
      note: batch.note,
      reviewing: true,
    );
    return const <ConversationEffect>[];
  }

  /// Lands the review, and with it the permission to analyse (ADR-0022).
  ///
  /// What arrives is the user's reading of the screen — their speakers, their
  /// words, their order — and it **replaces** the batch rather than sitting
  /// beside it: the next analysis is gated on this confirmation, so a
  /// confirmation that left the old transcript in place would be a dialog.
  ///
  /// The title and the app name the user entered are read the same way: a
  /// non-empty entry replaces the platform's own (or supplies the half the
  /// platform could not read at all — ADR-0030), and an empty entry leaves the
  /// platform's value where there was one. The confirmed identity rides the
  /// batch forward, so the round that follows is about the conversation the
  /// user just named.
  ///
  /// The source does not change. A batch read off a screenshot is still a batch
  /// read off a screenshot after a person has corrected it, so the lines keep
  /// their provenance and the model keeps being told where they came from
  /// (ADR-0022 decision 4). The note does change, because the old one asked the
  /// user to check the sides and the user just did.
  List<ConversationEffect> _onConfirmTranscript(
    List<ChatLine> lines, {
    String? title,
    String? appName,
  }) {
    final PanelBatch? batch = state.latest;
    if (batch == null) {
      return const <ConversationEffect>[];
    }
    final List<ChatLine> kept = <ChatLine>[
      for (final ChatLine line in lines)
        if (line.text.trim().isNotEmpty)
          ChatLine(speaker: line.speaker, text: line.text.trim()),
    ];
    // The panel disables its own button on an empty batch; this is the second
    // reading of the same rule, so a command that arrives anyway changes
    // nothing rather than replacing a conversation with nothing.
    if (kept.isEmpty) {
      return const <ConversationEffect>[];
    }
    final ConversationRef conversation = ConversationRef(
      packageName: batch.snapshot.conversation.packageName,
      appName: (appName == null || appName.trim().isEmpty)
          ? batch.snapshot.conversation.appName
          : appName.trim(),
      title: (title == null || title.trim().isEmpty)
          ? batch.snapshot.conversation.title
          : title.trim(),
    );
    state.latest = PanelBatch(
      snapshot: ChatUiSnapshot(
        conversation: conversation,
        lines: kept,
        capturedAt: batch.snapshot.capturedAt,
        reviewed: true,
      ),
      source: batch.source,
      note: const CopyNote(NoteCode.reviewed),
    );
    _publish(
      analysed: conversation,
      live: conversation,
      note: state.latest!.note,
      transcript: kept,
      reviewing: false,
    );
    return <ConversationEffect>[
      PersistIdentity(
        title: conversation.title ?? '',
        packageName: conversation.packageName,
        appName: conversation.appName ?? '',
        lines: kept,
      ),
    ];
  }

  /// Throws the batch away instead of confirming it (ADR-0022 decision 11).
  ///
  /// The batch goes with it, back to the state the panel was in before the
  /// capture: showing words the gate will refuse is worse than showing none,
  /// and the user asked for this one to be dropped rather than for an empty
  /// confirmation.
  List<ConversationEffect> _onCancelReview() {
    state.latest = null;
    _publish(
      analysed: ConversationRef.none,
      transcript: const <ChatLine>[],
      note: null,
      reviewing: false,
    );
    return const <ConversationEffect>[];
  }

  List<ConversationEffect> _onCopy(String? text) {
    if (text == null || text.isEmpty) {
      return const <ConversationEffect>[];
    }
    _publish(note: const CopyNote(NoteCode.copied));
    return <ConversationEffect>[WriteClipboard(text)];
  }

  // ------------------------------------------------------- the whole frame

  /// Photographs whatever is in front and reads the whole frame (ADR-0018).
  ///
  /// No window handle is passed, and the panel is not hidden here. `capture(null)`
  /// asks for the screen, which is the only question this command can ask: it
  /// exists for applications the adapter registry does not know, so there is no
  /// window to name. `findTargetWindow` answers a per-window question and answers
  /// it with the window that is *active*, which while the panel is up is liable
  /// to be the panel itself; worse, a handle taken before the panel comes off is
  /// stale by the time it arrives, and Android's `capture` refuses a handle that
  /// no longer matches the live window (-3, 「目标窗口已经切换」). Hiding the
  /// panel belongs to the implementation for the same reason the rate limit does
  /// (ADR-0009): macOS hides and restores inside its own `capture`, Android's
  /// native `ScreenCapture` does, and both restore in a `finally` that a failure
  /// here cannot reach.
  List<ConversationEffect> _onRecogniseOnce() {
    if (state.recognising) {
      return const <ConversationEffect>[];
    }
    state.recognising = true;
    _publish(note: const CopyNote(NoteCode.recognising));
    return const <ConversationEffect>[CaptureScreen()];
  }

  List<ConversationEffect> _onFrameCaptured(FrameCaptured event) =>
      <ConversationEffect>[RecogniseFrame(event.frame)];

  List<ConversationEffect> _onCaptureRefused(CaptureRefused event) {
    state.recognising = false;
    _publish(
      note: CopyNote(NoteCode.captureRefused, reason: event.reason),
    );
    return const <ConversationEffect>[];
  }

  /// The platform unable to answer at all.
  ///
  /// The contract reserves exceptions for exactly this, and on Android it is
  /// nearly always the accessibility service being off — the bridge cannot take
  /// a picture without it, so it raises this code before any capture machinery
  /// runs. Answering with the generic sentence would name a symptom the user
  /// cannot act on, which is what cost a code-reading session the first time
  /// this happened; the note names the permission instead, so the panel draws a
  /// button that opens the page rather than printing a description of it
  /// (ADR-0021 decision 8).
  ///
  /// Every other code keeps the generic sentence: the bridge's messages are
  /// written for a developer, not for the panel.
  List<ConversationEffect> _onCaptureThrew(CaptureThrew event) {
    state.recognising = false;
    _publish(
      note: event.code == captureServiceUnavailable
          ? const CopyNote(
              NoteCode.captureServiceOff,
              remedy: AskPermission(PermissionKind.accessibility),
            )
          : const CopyNote(NoteCode.captureFailed),
    );
    return const <ConversationEffect>[];
  }

  /// `MiaotouAndroidPlugin.withCaptureService`, which is the only place in the
  /// three ports that raises it.
  static const String captureServiceUnavailable =
      'accessibility_service_unavailable';

  List<ConversationEffect> _onRecognitionFailed() {
    state.recognising = false;
    _publish(note: const CopyNote(NoteCode.recogniseFailed));
    return const <ConversationEffect>[];
  }

  /// The reading half of the capture, once a frame is in hand.
  ///
  /// Straight into the review state (ADR-0022 decision 7): the gate would
  /// refuse the first analysis of this batch every time — every line of a
  /// capture carries the marker — so offering that analysis first would be a
  /// round trip that is known to fail.
  ///
  /// [LinesRecognised.at] is the caller's clock rather than this file's: a
  /// capture timestamp is a fact about the moment the platform answered, and
  /// nothing in this package reads one.
  List<ConversationEffect> _onLinesRecognised(LinesRecognised event) {
    state.recognising = false;
    final RecognisedCapture capture = groupRecognisedLines(
      event.lines,
      frame: event.frame,
    );
    if (capture.lines.isEmpty) {
      _publish(note: const CopyNote(NoteCode.nothingRecognised));
      return const <ConversationEffect>[];
    }
    state.latest = PanelBatch(
      snapshot: ChatUiSnapshot(
        // The conversation the capture is about is the one in front of the user,
        // not the last batch: a capture names the app it photographed, and the
        // last read (`state.live`) is the platform's word for what is in front.
        // Falling back to `none` is what used to make the review always ask for
        // the application by hand, even though the service had already named it.
        conversation:
            state.live ?? state.latest?.snapshot.conversation ?? ConversationRef.none,
        lines: capture.lines,
        capturedAt: event.at,
      ),
      source: capturedByCapture,
      note: CopyNote(
        capture.sidesSplit ? NoteCode.sidesGuessed : NoteCode.sidesNotSplit,
      ),
    );
    _publish(
      analysed: state.latest!.snapshot.conversation,
      live: state.latest!.snapshot.conversation,
      note: state.latest!.note,
      transcript: capture.lines,
      reviewing: true,
    );
    return const <ConversationEffect>[];
  }

  // ------------------------------------------------------------- a reading

  /// A pushed read, and the one thing it may not do.
  ///
  /// A pushed read with no lines is a conversation-identity event, not a
  /// reading of the conversation. Android's `AndroidConversationEvent` maps to
  /// `ChatUiSnapshot(lines: const [])`, and it fires on foreground changes and
  /// read-only flips — things that change *whose* conversation this is without
  /// carrying a single word of it. It must update what the panel calls the
  /// current conversation, but it has no lines to show, so it has no business
  /// ending a review in progress: the batch being edited is still the batch on
  /// the screen. Letting it end the review is exactly the defect where tapping
  /// a line to edit it — and the accessibility event that tap causes — wiped
  /// the batch out from under the user.
  ///
  /// The automatic round is asked for only when the signature moved. A re-read
  /// of the same screen is not a reason to spend a model call, and the signature
  /// is the port's own answer to "has this conversation moved on".
  List<ConversationEffect> _acceptSnapshot(ChatUiSnapshot snapshot) {
    if (snapshot.lines.isEmpty) {
      _publish(live: snapshot.conversation, note: state.note);
      return const <ConversationEffect>[];
    }
    final String previousSignature = state.latest?.snapshot.signature() ?? '';
    state.latest = PanelBatch.of(snapshot, source: pushedByTree);
    _publish(
      analysed: state.analysedSnapshot == null ? snapshot.conversation : null,
      live: snapshot.conversation,
      note: state.latest!.note,
      transcript: _transcriptOf(snapshot.lines),
      // A fresh read — one with words in it — supersedes whatever was being
      // reviewed. It is also what makes a reviewed batch stop being current
      // once the conversation moves on — the confirmation belongs to the screen
      // it was about.
      reviewing: false,
    );
    if (snapshot.signature() == previousSignature) {
      return const <ConversationEffect>[];
    }
    return const <ConversationEffect>[LoadAutoAnalyseSetting()];
  }

  List<ConversationEffect> _onAutoAnalyseRead(AutoAnalyseRead event) =>
      event.enabled
      ? _beginRound(manual: false)
      : const <ConversationEffect>[];

  // ---------------------------------------------------------------- a round

  /// Starts a round, or records that one is already running.
  ///
  /// A round the user asked for while one is in flight is dropped rather than
  /// queued: they can see that the panel is working, and a second press is a
  /// press on a button that is already doing the thing. An automatic round
  /// cannot be dropped the same way — the user did not press anything, so
  /// dropping it would lose the read that triggered it — and is deferred
  /// instead.
  List<ConversationEffect> _beginRound({required bool manual}) {
    if (state.round != null) {
      if (!manual) {
        state.pendingAutomaticAnalysis = true;
      }
      return const <ConversationEffect>[];
    }
    state.round = AnalysisRound();
    return const <ConversationEffect>[ReadTree(TreeReadPurpose.analysis)];
  }

  /// Ends the running round, and starts the deferred one if there is one.
  List<ConversationEffect> _endRound() {
    state.round = null;
    if (!state.pendingAutomaticAnalysis) {
      return const <ConversationEffect>[];
    }
    state.pendingAutomaticAnalysis = false;
    return _beginRound(manual: false);
  }

  List<ConversationEffect> _onAnalysisTreeAnswered(TreeAnswered event) {
    if (event.threw) {
      _publish(note: const CopyNote(NoteCode.analysisFailed));
      return _endRound();
    }
    final AnalysisRound round = state.round!;
    final PanelBatch? latest = state.latest;
    // ADR-0022 decision 18: an analysis reads the batch the user reviewed, not
    // a fresh read of the same screen. Re-reading here would answer about an
    // unreviewed copy of what was confirmed, and for a batch the domain refuses
    // that copy is refused the same way — so the confirmation would be thrown
    // away by the very next analysis. A new read still wins as soon as the
    // platform pushes one, because `_acceptSnapshot` replaces `latest` and
    // clears the flag with it.
    //
    // **The batch that wins is kept, not rebuilt.** Rebuilding it from its own
    // snapshot would drop the caveat the engine put on it — a reviewed batch's
    // reminder that a person read the screen is not a field on the snapshot,
    // precisely so that it cannot travel back out of this package as a sentence
    // — and the round would then finish by clearing the note the confirmation
    // just set.
    final ChatUiSnapshot? read = event.snapshot;
    final PanelBatch? batch = (latest?.snapshot.reviewed ?? false) || read == null
        ? latest
        : PanelBatch.of(read, source: pushedByTree);
    if (batch == null || batch.snapshot.lines.isEmpty) {
      _publish(note: const CopyNote(NoteCode.noConversation));
      return _endRound();
    }
    // ADR-0030: a round runs only once both halves of the conversation are
    // named — the application and the person. The application is named when it
    // has a package *or* a name the review supplied (a port with no tree cannot
    // read either, and the user enters the name by hand); the person is named
    // when the title is read. The review supplies the missing halves, so an
    // unnamed one here is the review not having been done, and the way out is
    // the review itself.
    if (ConversationLabel.of(batch.snapshot.conversation).kind !=
        ConversationLabelKind.appAndTitle) {
      _publish(
        note: const CopyNote(
          NoteCode.identityIncomplete,
          remedy: AskReview(),
        ),
      );
      return _endRound();
    }
    round.batch = batch;
    state.latest = batch;
    final bool hadAdvice = state.advice != null;
    state.advice = null;
    state.analysedSnapshot = null;
    _publish(
      analysed: batch.snapshot.conversation,
      live: batch.snapshot.conversation,
      note: const CopyNote(NoteCode.analysing),
      reviewing: false,
    );
    return <ConversationEffect>[
      // The advice on the panel belongs to the batch that was just cleared, so
      // whoever is showing it is told it is gone before the round starts —
      // otherwise the old drafts sit under a panel that says it is working.
      if (hadAdvice) const EmitAdvice(null),
      const LoadRoundSettings(),
    ];
  }

  List<ConversationEffect> _onRoundSettingsRead(RoundSettingsRead event) {
    final PanelBatch batch = state.round!.batch!;
    if (requiresConfiguredModels && !event.settings.isReady) {
      _publish(note: const CopyNote(NoteCode.configureModels));
      return _endRound();
    }
    return <ConversationEffect>[
      RunRound(
        snapshot: batch.snapshot,
        source: batch.source,
        settings: event.settings,
      ),
    ];
  }

  List<ConversationEffect> _onAnalysisSucceeded(AnalysisSucceeded event) {
    final PanelBatch batch = state.round!.batch!;
    state.analysedSnapshot = batch.snapshot;
    state.advice = event.advice;
    _publish(
      analysed: batch.snapshot.conversation,
      live: state.latest?.snapshot.conversation ?? batch.snapshot.conversation,
      advice: event.advice,
      note: batch.note,
    );
    return <ConversationEffect>[EmitAdvice(event.advice), ..._endRound()];
  }

  List<ConversationEffect> _onAnalysisRefused(AnalysisRefused event) {
    _publish(
      note: LiteralNote(
        event.message,
        remedy: _refusalRemedy(state.round?.batch),
      ),
    );
    return _endRound();
  }

  List<ConversationEffect> _onAnalysisFailed() {
    _publish(note: const CopyNote(NoteCode.analysisFailed));
    return _endRound();
  }

  /// The way out of the one refusal that has one (ADR-0022 decision 13).
  ///
  /// Asked with the domain's own predicate rather than by matching the
  /// sentence: `checkAnalysable` refuses for two reasons and the other one is a
  /// background that is too long, which no review can fix. This asks the gate
  /// the same question it was asked, over the same lines it was asked about, so
  /// the two cannot disagree about which refusal this is — which is why the
  /// batch goes through [snapshotOf] and not through a rendering of its own
  /// (ADR-0024).
  NoteRemedy? _refusalRemedy(PanelBatch? refused) {
    if (refused == null) {
      return null;
    }
    final Snapshot asDomain = snapshotOf(
      title: refused.snapshot.conversation.title,
      lines: refused.snapshot.lines,
      source: refused.source,
      reviewed: refused.snapshot.reviewed,
    );
    return allLinesUnconfirmed(asDomain.transcript) ? const AskReview() : null;
  }

  // ----------------------------------------------------------------- a fill

  List<ConversationEffect> _onFill(String? text) {
    final ChatUiSnapshot? analysed = state.analysedSnapshot;
    if (text == null || text.isEmpty || analysed == null) {
      return const <ConversationEffect>[];
    }
    state.fill = FillAttempt(text: text, analysed: analysed);
    return const <ConversationEffect>[ReadTree(TreeReadPurpose.fill)];
  }

  /// The re-read that guards a fill.
  ///
  /// Null is the honest answer on the ports with no node tree: «the screen has
  /// not changed» cannot be established by re-reading something that cannot be
  /// re-read, and filling a reply into a conversation nobody verified is worse
  /// than declining. Both failures take the branch below and the reply is not
  /// filled.
  ///
  /// A reader that *threw* takes it too, and that is a small change: before
  /// this the exception left the command unawaited and reached nobody, so the
  /// user pressed 填入 and watched nothing happen. A fill that could not be
  /// guarded is a fill that is not attempted, which is what the note says. The
  /// console trace is given up for it.
  List<ConversationEffect> _onFillTreeAnswered(TreeAnswered event) {
    final FillAttempt? attempt = state.fill;
    if (attempt == null) {
      return const <ConversationEffect>[];
    }
    final ChatUiSnapshot? current = event.snapshot;
    if (event.threw ||
        current == null ||
        current.conversation != attempt.analysed.conversation ||
        current.signature() != attempt.analysed.signature()) {
      state.fill = null;
      _publish(
        live: current?.conversation ?? state.latest?.snapshot.conversation,
        note: const CopyNote(NoteCode.conversationChanged),
      );
      return const <ConversationEffect>[];
    }
    return const <ConversationEffect>[FindFillTarget()];
  }

  List<ConversationEffect> _onFillTargetResolved(FillTargetResolved event) {
    final FillAttempt? attempt = state.fill;
    if (attempt == null) {
      return const <ConversationEffect>[];
    }
    final String? windowId = event.windowId;
    if (windowId == null) {
      state.fill = null;
      _publish(note: const CopyNote(NoteCode.conversationChanged));
      return const <ConversationEffect>[];
    }
    return <ConversationEffect>[InjectText(windowId: windowId, text: attempt.text)];
  }

  /// The text is somewhere the user can use, or it is not.
  ///
  /// An unverified landing falls back to the clipboard rather than to a retry:
  /// a retry is a second injection into a conversation nobody has verified, and
  /// the user is standing in front of the input box with the text on their
  /// clipboard and can see for themselves what happened.
  List<ConversationEffect> _onInjectionResolved(InjectionResolved event) {
    final FillAttempt? attempt = state.fill;
    state.fill = null;
    if (attempt == null) {
      return const <ConversationEffect>[];
    }
    if (event.verified) {
      _publish(note: const CopyNote(NoteCode.filled));
      return const <ConversationEffect>[];
    }
    _publish(note: const CopyNote(NoteCode.fillUnverified));
    return <ConversationEffect>[WriteClipboard(attempt.text)];
  }

  List<ConversationEffect> _onDisposed() {
    state.disposed = true;
    return const <ConversationEffect>[];
  }

  // ------------------------------------------------------------ the state

  /// Everything the panel shows, replaced in the one place that does it.
  ///
  /// The fallbacks are the whole of the rule and they are not the same for
  /// every field. `note` has **none**: a note is about the frame that just
  /// happened, so a caller that does not pass one is clearing it, and every
  /// call site says which it means. `live` falls back through `latest` before
  /// it falls back to itself, because the conversation in front of the user is
  /// whatever was last read.
  void _publish({
    ConversationRef? analysed,
    ConversationRef? live,
    Advice? advice,
    ConversationNote? note,
    List<ChatLine>? transcript,
    bool? reviewing,
  }) {
    state.analysed = analysed ?? state.analysed;
    state.live = live ?? state.latest?.snapshot.conversation ?? state.live;
    state.advice = advice ?? state.advice;
    state.note = note;
    state.transcript = transcript ?? state.transcript;
    state.reviewing = reviewing ?? state.reviewing;
  }
}

/// Which read answered, so that one event can serve three callers that treat a
/// failure differently.
///
/// The three read different things for the same reason and are caught by three
/// different `try`s in the original: a start that cannot read has nothing to
/// show, an analysis that cannot read has to tell the user it failed, and a fill
/// that cannot read must not write. Keeping the purpose on the event is what
/// lets the caller report all three through one door without deciding anything.
enum TreeReadPurpose { start, analysis, fill }

/// The batch on the panel: a reading, how it was obtained, and what it said
/// about itself.
///
/// The three travel together because they are one fact. `source` used to be a
/// second field beside the snapshot and drifted from it — it was set in four
/// places and read in one — and the caveat used to live *inside* the snapshot as
/// a finished sentence, which is how copy came to sit in a value the domain
/// builds.
final class PanelBatch {
  const PanelBatch({required this.snapshot, required this.source, this.note});

  /// A batch the platform produced, taking the caveat the platform put on it.
  ///
  /// A pushed reading may carry its own note — the tree saying the lines came
  /// from the OCR fallback, for instance — and that is somebody else's sentence,
  /// so it travels on as one.
  factory PanelBatch.of(ChatUiSnapshot snapshot, {required String source}) =>
      PanelBatch(
        snapshot: snapshot,
        source: source,
        note: snapshot.note == null ? null : LiteralNote(snapshot.note!),
      );

  final ChatUiSnapshot snapshot;

  /// How [snapshot] was obtained: [pushedByTree] or [capturedByCapture].
  final String source;

  /// What to say about how this batch was produced.
  final ConversationNote? note;
}

/// A round that is in flight, and the batch it settled on.
///
/// Null [batch] means the read has not answered yet, which is a state the user
/// can see: the panel is already saying 分析中.
final class AnalysisRound {
  PanelBatch? batch;
}

/// A fill that is in flight, and what it is filling.
///
/// Held rather than passed because the fill is three effects long — re-read,
/// find the window, inject — and the text has to survive all three.
final class FillAttempt {
  const FillAttempt({required this.text, required this.analysed});

  final String text;

  /// The batch the advice belongs to. A fill writes into a specific thread, and
  /// the guard is whether that thread is still the one in front.
  final ChatUiSnapshot analysed;
}

/// Everything the panel is showing, and everything in flight.
///
/// Mutable and written only by [ConversationEngine]. The caller reads it; a
/// caller that wrote to it would be a second state machine.
final class ConversationState {
  ConversationState();

  /// The batch on the panel, or null before anything has been read.
  PanelBatch? latest;

  /// The batch the last round agreed to work on. Null while a round is running
  /// and before any round has finished.
  ChatUiSnapshot? analysedSnapshot;

  /// The verdict and the drafts, or null when there have been none.
  Advice? advice;

  /// Whose analysis is on the panel. [ConversationRef.none] before the first.
  ConversationRef analysed = ConversationRef.none;

  /// What the user is looking at. Null until something has been read.
  ConversationRef? live;

  /// What to say about the frame that just happened, if anything.
  ConversationNote? note;

  /// The batch the panel is showing, line by line.
  ///
  /// Published for **every** source rather than only for a capture (ADR-0022
  /// decision 17), because the review surface serves any batch and the standing
  /// 「核对」 button has nothing to be about otherwise.
  List<ChatLine> transcript = const <ChatLine>[];

  /// True while the panel is asking the user to read the batch and confirm it.
  bool reviewing = false;

  /// The round in flight, or null.
  AnalysisRound? round;

  /// A round that was asked for while one was running, waiting for it to end.
  bool pendingAutomaticAnalysis = false;

  /// The fill in flight, or null.
  FillAttempt? fill;

  /// True from the moment a capture is asked for until it has been read.
  bool recognising = false;

  /// True once the caller has taken this engine out of service.
  bool disposed = false;
}

/// Something the engine wants done.
///
/// Every one of these is an await, and none of them decides anything: the engine
/// has already decided what the answer will mean, which is why a result comes
/// back as an event and not as a return value.
sealed class ConversationEffect {
  const ConversationEffect();
}

/// Read whatever conversation the platform can see.
final class ReadTree extends ConversationEffect {
  const ReadTree(this.purpose);

  final TreeReadPurpose purpose;
}

/// Photograph the screen.
final class CaptureScreen extends ConversationEffect {
  const CaptureScreen();
}

/// Read the frame that was just taken.
final class RecogniseFrame extends ConversationEffect {
  const RecogniseFrame(this.frame);

  final CaptureFrame frame;
}

/// Read whether the user wants rounds to start by themselves.
final class LoadAutoAnalyseSetting extends ConversationEffect {
  const LoadAutoAnalyseSetting();
}

/// Read the settings a round needs.
final class LoadRoundSettings extends ConversationEffect {
  const LoadRoundSettings();
}

/// Run one round: strategy, drafts, ranking.
final class RunRound extends ConversationEffect {
  const RunRound({
    required this.snapshot,
    required this.source,
    required this.settings,
  });

  final ChatUiSnapshot snapshot;
  final String source;
  final ModelSettings settings;
}

/// Tell whoever is showing the advice that it changed, including when it went
/// away.
final class EmitAdvice extends ConversationEffect {
  const EmitAdvice(this.advice);

  final Advice? advice;
}

/// Open the system page for one permission.
final class OpenPermissionSettings extends ConversationEffect {
  const OpenPermissionSettings(this.kind);

  final PermissionKind kind;
}

/// Put text on the clipboard.
final class WriteClipboard extends ConversationEffect {
  const WriteClipboard(this.text);

  final String text;
}

/// Ask the platform which window a fill should land in.
final class FindFillTarget extends ConversationEffect {
  const FindFillTarget();
}

/// Put text into a window's input box.
final class InjectText extends ConversationEffect {
  const InjectText({required this.windowId, required this.text});

  final String windowId;
  final String text;
}

/// Remember the identity a review confirmed, into the knowledge base (ADR-0030).
///
/// The person half becomes a contact (merged by name, not duplicated), and an
/// application name entered with no package behind it is stored under the name
/// itself as the key. What to write is the runtime's call — the engine only
/// reports the identity that was confirmed and lets the implementation decide
/// which halves are worth keeping.
final class PersistIdentity extends ConversationEffect {
  const PersistIdentity({
    required this.title,
    required this.packageName,
    required this.appName,
    this.lines = const <ChatLine>[],
  });

  final String title;
  final String packageName;
  final String appName;

  /// The confirmed lines, so the runtime can append this round's history to the
  /// contact instead of only remembering who they are.
  final List<ChatLine> lines;
}

/// Something that happened, as the engine sees it.
sealed class ConversationEvent {
  const ConversationEvent();
}

/// The caller is starting the engine.
final class Started extends ConversationEvent {
  const Started();
}

/// The caller is taking the engine out of service.
final class EngineDisposed extends ConversationEvent {
  const EngineDisposed();
}

/// One read of the tree came back, or did not.
final class TreeAnswered extends ConversationEvent {
  const TreeAnswered(this.purpose, {this.snapshot, this.threw = false});

  final TreeReadPurpose purpose;

  /// The reading, or null for "this port has no tree to read".
  ///
  /// Not a failure: [UiTreeReader] is the member Android answers and the two
  /// desktop ports refuse (ADR-0009 decision 2), and the refusal is a statement
  /// about the platform rather than a failure of the read.
  final ChatUiSnapshot? snapshot;

  /// The reader threw rather than answering.
  ///
  /// The typed refusal is [snapshot] being null instead. A reader that is broken
  /// rather than refusing stays visible, because swallowing a defect into the
  /// same null would make a crash and a desktop port indistinguishable.
  final bool threw;
}

/// The platform pushed a reading of the screen.
final class SnapshotPushed extends ConversationEvent {
  const SnapshotPushed(this.snapshot);

  final ChatUiSnapshot snapshot;
}

/// The pushed-read stream errored.
final class SnapshotStreamFailed extends ConversationEvent {
  const SnapshotStreamFailed();
}

/// The panel asked for something.
final class CommandReceived extends ConversationEvent {
  const CommandReceived(
    this.kind, {
    this.text,
    this.permission,
    this.lines,
    this.title,
    this.appName,
  });

  final ConversationCommandKind kind;

  /// The user-edited draft, for [ConversationCommandKind.fill] and
  /// [ConversationCommandKind.copy].
  final String? text;

  /// Which system page, for [ConversationCommandKind.openPermissionSettings].
  final PermissionKind? permission;

  /// The batch as the user left it, for
  /// [ConversationCommandKind.confirmTranscript].
  ///
  /// Null for every other command, which is what keeps "no lines" distinct from
  /// "an empty batch" — the latter is refused by the panel, which disables the
  /// button rather than sending it.
  final List<ChatLine>? lines;

  /// The thread title the user entered, for [ConversationCommandKind.
  /// confirmTranscript]. Null or blank means "leave the platform's reading".
  final String? title;

  /// The application name the user entered, for [ConversationCommandKind.
  /// confirmTranscript]. Null or blank means "leave the platform's reading".
  final String? appName;
}

/// One thing the panel is asking for, in this package's own words.
///
/// A second enum rather than a shared one, because the panel's own vocabulary
/// lives in the application (it is a value that crosses between two windows,
/// which this package has no business knowing about) and this package cannot
/// import it. The two are kept in step by a gate in the application's suite
/// rather than by one of them being derived from the other, because a mapping
/// that is checked is a mapping that cannot silently lose a command.
enum ConversationCommandKind {
  fill,
  copy,
  details,
  reanalyse,
  analyseCurrent,
  recogniseOnce,
  close,
  openPermissionSettings,
  openReview,
  confirmTranscript,
  cancelReview,
}

/// A frame was taken.
final class FrameCaptured extends ConversationEvent {
  const FrameCaptured(this.frame);

  final CaptureFrame frame;
}

/// A frame was refused, and the platform said why in its own words.
///
/// Android's `ScreenCapture` writes these to be shown unchanged — they name the
/// cause and, where there is one, the remedy — and `CaptureFailed.code` is
/// deliberately untranslated, so passing the sentence through keeps both the
/// taxonomy and the advice.
final class CaptureRefused extends ConversationEvent {
  const CaptureRefused(this.reason);

  final String reason;
}

/// The platform could not answer at all, and named a code for it.
final class CaptureThrew extends ConversationEvent {
  const CaptureThrew({this.code});

  /// A `PlatformException`'s code, or null for a throw that is not one.
  final String? code;
}

/// A frame was taken and could not be read.
final class RecognitionFailed extends ConversationEvent {
  const RecognitionFailed();
}

/// A frame was read.
final class LinesRecognised extends ConversationEvent {
  const LinesRecognised({
    required this.frame,
    required this.lines,
    required this.at,
  });

  /// The frame the lines came off, which the grouping needs for its geometry.
  final CaptureFrame frame;

  final List<OcrLine> lines;

  /// When the reading came back, from the caller's clock.
  final DateTime at;
}

/// The auto-analyse setting was read.
final class AutoAnalyseRead extends ConversationEvent {
  const AutoAnalyseRead(this.enabled);

  final bool enabled;
}

/// The round's settings were read.
final class RoundSettingsRead extends ConversationEvent {
  const RoundSettingsRead(this.settings);

  final ModelSettings settings;
}

/// A round produced a verdict.
final class AnalysisSucceeded extends ConversationEvent {
  const AnalysisSucceeded(this.advice);

  final Advice advice;
}

/// A round was refused by the domain itself.
final class AnalysisRefused extends ConversationEvent {
  const AnalysisRefused(this.message);

  final String message;
}

/// A round threw something that is not the domain's own refusal.
final class AnalysisFailed extends ConversationEvent {
  const AnalysisFailed();
}

/// The fill target was resolved.
final class FillTargetResolved extends ConversationEvent {
  const FillTargetResolved(this.windowId);

  final String? windowId;
}

/// The injection came back.
final class InjectionResolved extends ConversationEvent {
  const InjectionResolved(this.verified);

  /// Whether the text was seen where it was supposed to land.
  final bool verified;
}

/// The contact a confirmed name belongs to, merged rather than duplicated.
///
/// A name the knowledge base already holds — matched case-insensitively against
/// a contact's `name` — gains the new package instead of becoming a second
/// contact for the same person. A name it does not hold becomes a new contact
/// keyed by a timestamp id. The aliases and every other field the existing
/// contact carried are kept: only the package list (and its display name) change
/// (ADR-0030).
KnowledgeContact contactForName({
  required List<KnowledgeContact> existing,
  required String name,
  required String packageName,
  required String appName,
  required DateTime now,
}) {
  final String wanted = name.trim();
  for (final KnowledgeContact contact in existing) {
    if (contact.name.trim().toLowerCase() != wanted.toLowerCase()) {
      continue;
    }
    if (packageName.isEmpty || contact.packageNames.contains(packageName)) {
      return _withAppName(contact, packageName, appName, now);
    }
    return _withAppName(
      KnowledgeContact(
        id: contact.id,
        name: contact.name,
        updatedAt: now,
        aliases: contact.aliases,
        packageNames: <String>[...contact.packageNames, packageName],
        packageAppNames: contact.packageAppNames,
        relationship: contact.relationship,
        notes: contact.notes,
        stage: contact.stage,
        goal: contact.goal,
        autoSummary: contact.autoSummary,
      ),
      packageName,
      appName,
      now,
    );
  }
  return _withAppName(
    KnowledgeContact(
      id: 'contact-${now.microsecondsSinceEpoch}',
      name: wanted,
      updatedAt: now,
      packageNames: packageName.isEmpty
          ? const <String>[]
          : <String>[packageName],
    ),
    packageName,
    appName,
    now,
  );
}

/// Records [appName] against [packageName] when both are present, leaving the
/// contact untouched otherwise. The display name rides beside the package so the
/// knowledge base groups by what a person reads rather than the id.
KnowledgeContact _withAppName(
  KnowledgeContact contact,
  String packageName,
  String appName,
  DateTime now,
) {
  final String trimmedApp = appName.trim();
  if (packageName.isEmpty || trimmedApp.isEmpty) {
    return contact;
  }
  if (contact.packageAppNames[packageName] == trimmedApp) {
    return contact;
  }
  return KnowledgeContact(
    id: contact.id,
    name: contact.name,
    updatedAt: now,
    aliases: contact.aliases,
    packageNames: contact.packageNames,
    packageAppNames: <String, String>{
      ...contact.packageAppNames,
      packageName: trimmedApp,
    },
    relationship: contact.relationship,
    notes: contact.notes,
    stage: contact.stage,
    goal: contact.goal,
    autoSummary: contact.autoSummary,
  );
}
