import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../panel/protocol.dart';
import '../panel/session.dart';
import 'model_settings.dart';
import 'model_transport.dart';
import 'manual_recognition.dart';

typedef ConversationAnalyzer = Future<Advice> Function(
  ChatUiSnapshot snapshot,
  ModelSettings settings,
);

final class ConversationRuntime {
  ConversationRuntime({
    required this.capabilities,
    required this.panel,
    required this.copy,
    required this.clipboardWrite,
    this.onAdvice,
    ConversationAnalyzer? analyzer,
  }) : _customAnalyzer = analyzer;

  final CapabilitySet capabilities;
  final PanelSession panel;
  final AppCopy copy;
  final FutureOr<void> Function(String text) clipboardWrite;
  final ValueChanged<Advice?>? onAdvice;
  final ConversationAnalyzer? _customAnalyzer;

  StreamSubscription<ChatUiSnapshot>? _snapshotSubscription;
  StreamSubscription<PanelCommand>? _commandSubscription;
  ChatUiSnapshot? _latest;
  ChatUiSnapshot? _analysedSnapshot;

  /// How [_latest] was obtained, for the transcript's own `source` field.
  ///
  /// Today it distinguishes the one path whose provenance we know for certain —
  /// a manual whole-frame capture, which is OCR by construction (ADR-0018) — from
  /// everything else. An event the platform pushes is called `accessibility`
  /// whether or not the retained service reached it through its own OCR
  /// fallback, because the wire carries no provenance; that gap predates this
  /// field and is recorded rather than papered over.
  String _latestSource = 'accessibility';

  /// The source of the snapshot a running analysis is reading.
  ///
  /// A field rather than a parameter because [ConversationAnalyzer] is the
  /// public seam a test substitutes, and widening it to carry provenance would
  /// push a platform detail through every caller to reach one of them.
  String _sourceOfCurrent = 'accessibility';
  Advice? _advice;
  SharedMaterial? _material;
  bool _analysing = false;
  bool _recognising = false;
  bool _pendingAutomaticAnalysis = false;
  bool _disposed = false;

  Future<void> start() async {
    _snapshotSubscription = _subscribeToPushedReads();
    _commandSubscription = panel.commands.listen(_handleCommand);
    try {
      final ChatUiSnapshot? initial = await _readTree();
      if (initial != null) {
        _acceptSnapshot(initial);
      }
    } on Object {
      _publish(note: _note(CopyKey.runtimeNoConversation));
    }
  }

  /// The screen's own reading of itself, or null where this port has no such
  /// reading to offer.
  ///
  /// [UiTreeReader] is the member of the contract Android answers and the two
  /// desktop ports refuse (ADR-0009 decision 2): macOS and Windows read pixels
  /// and recover the words through OCR, so there is no node tree to ask for and
  /// — permanently, not for this milestone — never will be. The refusal is a
  /// statement about the platform rather than a failure, and turning it into
  /// "no snapshot" is what lets the rest of this file keep asking one question,
  /// «what is on screen», instead of branching on the port at every call site.
  ///
  /// `on UnsupportedError` catches the narrower `UnimplementedError` with it,
  /// which is the SDK's own hierarchy and not an oversight — a not-yet is an
  /// `UnsupportedError` too. Both mean the same thing here, «ask the capture path
  /// instead», so they share one clause; where the two must be told apart
  /// `askCapability` is the one that does it.
  ///
  /// **Nothing that is not the typed refusal is caught here.** A reader that is
  /// broken rather than refusing still throws, so `start` reports it and
  /// `_analyze` reports it — a defect has to stay visible, and swallowing it
  /// into the same null would make a crash and a desktop port indistinguishable.
  ///
  /// **A null is not an empty conversation, and the caller must not treat it as
  /// one.** On these ports the way in is a whole-frame capture (ADR-0018),
  /// which is already the path a user takes for an application the adapter
  /// registry does not know — the same road, one reason further along.
  Future<ChatUiSnapshot?> _readTree() async {
    try {
      return await capabilities.uiTreeReader.readActiveChat();
    } on UnsupportedError {
      return null;
    }
  }

  /// The platform pushing a reading of the screen, on the ports that push one.
  ///
  /// Same refusal, same answer as [_readTree], and for the same reason: a port
  /// with no node tree has no stream to subscribe to. Null rather than an empty
  /// stream is the point — an empty stream is a live-looking thing that will
  /// never speak, which is exactly the shape ADR-0009 forbids an implementation
  /// to answer with. Here the caller is the one deciding, and "this port does
  /// not push" is a fact the rest of the runtime already handles: without a
  /// pushed read, the batch in play is the one a capture produced.
  StreamSubscription<ChatUiSnapshot>? _subscribeToPushedReads() {
    try {
      return capabilities.uiTreeReader.snapshots.listen(
        _acceptSnapshot,
        onError: (_) {
          _publish(note: _note(CopyKey.runtimeNoConversation));
        },
      );
    } on UnsupportedError {
      return null;
    }
  }

  void _acceptSnapshot(ChatUiSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    // A pushed read with no lines is a conversation-identity event, not a
    // reading of the conversation. Android's `AndroidConversationEvent` maps to
    // `ChatUiSnapshot(lines: const [])`, and it fires on foreground changes and
    // read-only flips — things that change *whose* conversation this is without
    // carrying a single word of it. It must update what the panel calls the
    // current conversation, but it has no lines to show, so it has no business
    // ending a review in progress: the batch being edited is still the batch on
    // the screen. Letting it end the review is exactly the defect where tapping
    // a line to edit it — and the accessibility event that tap causes — wiped
    // the batch out from under the user.
    if (snapshot.lines.isEmpty) {
      _publish(live: snapshot.conversation, note: panel.current.note);
      return;
    }
    final String previousSignature = _latest?.signature() ?? '';
    _latest = snapshot;
    _latestSource = 'accessibility';
    _publish(
      analysed: _analysedSnapshot == null ? snapshot.conversation : null,
      live: snapshot.conversation,
      note: _caveat(snapshot.note),
      transcript: _panelLines(snapshot.lines),
      // A fresh read — one with words in it — supersedes whatever was being
      // reviewed. It is also what makes a reviewed batch stop being current
      // once the conversation moves on — the confirmation belongs to the screen
      // it was about.
      reviewing: false,
    );
    if (snapshot.signature() == previousSignature) {
      return;
    }
    unawaited(_autoAnalyzeIfEnabled());
  }

  Future<void> _autoAnalyzeIfEnabled() async {
    final ModelSettings settings = await ModelSettings.load(
      capabilities.preferences,
      capabilities.secretStore,
    );
    if (settings.autoAnalyze) {
      await _analyze(manual: false);
    }
  }

  void _handleCommand(PanelCommand command) {
    switch (command.kind) {
      case PanelCommandKind.analyseCurrent:
      case PanelCommandKind.reanalyse:
        unawaited(_analyze(manual: true));
      case PanelCommandKind.recogniseOnce:
        unawaited(_recogniseOnce());
      case PanelCommandKind.copy:
        unawaited(_copy(command.text));
      case PanelCommandKind.fill:
        unawaited(_fill(command.text));
      case PanelCommandKind.details:
      case PanelCommandKind.close:
        break;
      case PanelCommandKind.openPermissionSettings:
        if (command.permission case final PermissionKind kind) {
          unawaited(_openPermissionSettings(kind));
        }
      case PanelCommandKind.openReview:
        _openReview();
      case PanelCommandKind.confirmTranscript:
        _confirmTranscript(command.lines ?? const <PanelLine>[]);
      case PanelCommandKind.cancelReview:
        _cancelReview();
    }
  }

  /// The batch on the panel, as the panel shows a line.
  ///
  /// The rectangle a captured line may carry stays on this side: the panel has
  /// nowhere to point at, and [PanelLine] is deliberately speaker and text.
  List<PanelLine> _panelLines(List<ChatLine> lines) => <PanelLine>[
    for (final ChatLine line in lines)
      PanelLine(speaker: line.speaker, text: line.text),
  ];

  /// Puts the batch on the panel into the review state (ADR-0022).
  ///
  /// The panel asks for a state and not for data: the lines it has to edit are
  /// the ones it is already being shown, and the runtime is the side that holds
  /// the batch. So this republishes with `reviewing` set and leaves the
  /// transcript where it is. Both doors arrive here — the standing 「核对」
  /// button and the 「去核对」 of a refusal — because they ask for the same
  /// thing and the engine already knows which batch is on the panel.
  void _openReview() {
    final ChatUiSnapshot? batch = _latest;
    if (batch == null || batch.lines.isEmpty) {
      _publish(note: _note(CopyKey.runtimeNoConversation));
      return;
    }
    _publish(
      analysed: batch.conversation,
      live: batch.conversation,
      note: _caveat(batch.note),
      reviewing: true,
    );
  }

  /// Lands the review, and with it the permission to analyse (ADR-0022).
  ///
  /// What arrives is the user's reading of the screen — their speakers, their
  /// words, their order — and it **replaces** the batch rather than sitting
  /// beside it: the next analysis is gated on this confirmation, so a
  /// confirmation that left the old transcript in place would be a dialog.
  ///
  /// The source does not change. A batch read off a screenshot is still a batch
  /// read off a screenshot after a person has corrected it, so the lines keep
  /// their provenance and the model keeps being told where they came from
  /// (ADR-0022 decision 4). The note does change, because the old one asked the
  /// user to check the sides and the user just did.
  void _confirmTranscript(List<PanelLine> lines) {
    final ChatUiSnapshot? batch = _latest;
    if (batch == null) {
      return;
    }
    final List<PanelLine> kept = <PanelLine>[
      for (final PanelLine line in lines)
        if (line.text.trim().isNotEmpty)
          PanelLine(speaker: line.speaker, text: line.text.trim()),
    ];
    // The panel disables its own button on an empty batch; this is the second
    // reading of the same rule, so a command that arrives anyway changes
    // nothing rather than replacing a conversation with nothing.
    if (kept.isEmpty) {
      return;
    }
    final ChatUiSnapshot reviewed = ChatUiSnapshot(
      conversation: batch.conversation,
      lines: <ChatLine>[
        for (final PanelLine line in kept)
          ChatLine(speaker: line.speaker, text: line.text),
      ],
      capturedAt: batch.capturedAt,
      note: copy.text(CopyKey.panelNoteReviewed),
      reviewed: true,
    );
    _latest = reviewed;
    _publish(
      analysed: reviewed.conversation,
      live: reviewed.conversation,
      note: _caveat(reviewed.note),
      transcript: kept,
      reviewing: false,
    );
  }

  /// Throws the batch away instead of confirming it (ADR-0022 decision 11).
  ///
  /// The batch goes with it, back to the state the panel was in before the
  /// capture: showing words the gate will refuse is worse than showing none,
  /// and the user asked for this one to be dropped rather than for an empty
  /// confirmation.
  void _cancelReview() {
    _latest = null;
    _latestSource = 'accessibility';
    _publish(
      analysed: ConversationRef.none,
      transcript: const <PanelLine>[],
      note: null,
      reviewing: false,
    );
  }

  /// The panel asking to be taken to a system page (ADR-0021 decision 8).
  ///
  /// The panel knows a [PermissionKind] and nothing else — which is what keeps
  /// `ACTION_ACCESSIBILITY_SETTINGS` and `ACTION_MANAGE_OVERLAY_PERMISSION` out
  /// of the panel engine entirely, exactly as every other command here keeps a
  /// platform detail on this side of the window boundary.
  ///
  /// A failure is swallowed, and deliberately rather than by omission: the panel
  /// that asked is the only surface that could report it, it asked *because* it
  /// is stuck, and turning a failed jump into a second note would replace one
  /// dead end with another. The settings section reads the same state and is the
  /// surface that can say the jump did not happen.
  Future<void> _openPermissionSettings(PermissionKind kind) async {
    try {
      await capabilities.permissions.openSettings(kind);
    } on Object {
      // Nothing to do with it here — see the note above.
    }
  }

  /// Photographs whatever is in front and reads the whole frame (ADR-0018).
  ///
  /// Composed from contract members rather than handed to the platform, which is
  /// what keeps ADR-0009's boundary intact and puts the grouping and the side
  /// guess in pure Dart where a fixture can pin them.
  ///
  /// No window handle is passed, and the panel is not hidden here.
  ///
  /// `capture(null)` asks for the screen, which is the only question this command
  /// can ask: it exists for applications the adapter registry does not know, so
  /// there is no window to name. `findTargetWindow` answers a per-window question
  /// and answers it with the window that is *active*, which while the panel is up
  /// is liable to be the panel itself. Worse, a handle taken before the panel
  /// comes off is stale by the time it arrives: Android's `capture` refuses a
  /// handle that no longer matches the live window (-3, 「目标窗口已经切换」), and
  /// hiding is exactly what changes it. The retired port's manual path passed no
  /// handle either.
  ///
  /// Hiding the panel belongs to the implementation for the same reason the rate
  /// limit does (ADR-0009): macOS hides and restores inside its own `capture`,
  /// Android's native `ScreenCapture` does, and both restore in a `finally` that
  /// a failure here cannot reach. Doing it at this level hid the panel twice and,
  /// by invalidating the handle, was most of why this command failed.
  ///
  /// This is the only way in for an application with no adapter, so a failure
  /// here has to say why rather than leave the user with an unchanged panel.
  Future<void> _recogniseOnce() async {
    if (_recognising || _disposed) {
      return;
    }
    _recognising = true;
    _publish(note: _note(CopyKey.runtimeRecognising));
    try {
      switch (await capabilities.screenCapture.capture()) {
        case CaptureFailed(:final String message):
          _publish(note: _refusal(message));
        case CaptureOk(:final CaptureFrame frame):
          await _readFrame(frame);
      }
    } on PlatformException catch (failure) {
      _publish(note: _platformRefusal(failure));
    } on Object {
      // The platform declining to answer at all — a channel that is gone, a
      // bridge that never attached — rather than declining this particular
      // frame.
      _publish(note: _note(CopyKey.runtimeCaptureFailed));
    } finally {
      _recognising = false;
    }
  }

  /// The reading half of [_recogniseOnce], once a frame is in hand.
  ///
  /// Separate from the capture so the two failures stay distinguishable: a frame
  /// we could not take and a frame we could not read both end in the panel, and
  /// the panel is the only channel there is — nothing writes these to a log.
  Future<void> _readFrame(CaptureFrame frame) async {
    final List<OcrLine> recognised;
    try {
      recognised = await capabilities.ocr.recognize(
        frame,
        languages: const <String>['zh-Hans'],
      );
    } on Object {
      _publish(note: _note(CopyKey.runtimeRecogniseFailed));
      return;
    }
    final RecognisedCapture capture = groupRecognisedLines(
      recognised,
      frame: frame,
    );
    if (capture.lines.isEmpty) {
      _publish(note: _note(CopyKey.runtimeNothingRecognised));
      return;
    }
    final ChatUiSnapshot snapshot = ChatUiSnapshot(
      conversation: _latest?.conversation ?? ConversationRef.none,
      lines: capture.lines,
      capturedAt: DateTime.now(),
      note: copy.text(
        capture.sidesSplit
            ? CopyKey.panelNoteSidesGuessed
            : CopyKey.panelNoteSidesNotSplit,
      ),
    );
    _latest = snapshot;
    _latestSource = 'ocr';
    // Straight into the review state (ADR-0022 decision 7): the gate would
    // refuse the first analysis of this batch every time — every line of a
    // capture carries the marker — so offering that analysis first would be a
    // round trip that is known to fail.
    _publish(
      analysed: snapshot.conversation,
      live: snapshot.conversation,
      note: _caveat(snapshot.note),
      transcript: _panelLines(capture.lines),
      reviewing: true,
    );
  }

  /// The platform's own words for a frame that was refused.
  ///
  /// Android's `ScreenCapture` writes these to be shown unchanged — they name the
  /// cause and, where there is one, the remedy — and [CaptureFailed.code] is
  /// deliberately untranslated, so passing the sentence through keeps both the
  /// taxonomy and the advice. A sentence of our own here would be the only thing
  /// standing between the user and the reason.
  PanelNote _refusal(String reason) => PanelNote(
    copy.text(CopyKey.runtimeCaptureRefused).replaceAll('{reason}', reason),
  );

  /// The one platform error that has a remedy of its own.
  ///
  /// The contract reserves exceptions for the platform being unable to answer
  /// at all, and on Android that is nearly always the accessibility service
  /// being off — the bridge cannot take a picture without it, so it raises this
  /// code before any capture machinery runs. Answering with the generic
  /// sentence would name a symptom the user cannot act on («确认已开启无障碍»
  /// when the panel cannot tell them *that* is what is wrong), which is what
  /// cost a code-reading session the first time this happened.
  ///
  /// Since ADR-0021 decision 8 the sentence is not the end of it: the note names
  /// [PermissionKind.accessibility], so the panel draws a button that opens the
  /// page rather than printing a description of it. That is the second half of
  /// the same repair — the first was saying which thing was off, this is taking
  /// the user there.
  ///
  /// Every other platform error keeps the generic sentence: the bridge's
  /// messages are written for a developer, not for the panel.
  PanelNote _platformRefusal(PlatformException failure) =>
      failure.code == _serviceUnavailable
          ? PanelNote(
              copy.text(CopyKey.runtimeCaptureServiceOff),
              remedy: const OpenPermissionPage(PermissionKind.accessibility),
            )
          : _note(CopyKey.runtimeCaptureFailed);

  /// `MiaotouAndroidPlugin.withCaptureService`, which is the only place in the
  /// three ports that raises it.
  static const String _serviceUnavailable = 'accessibility_service_unavailable';

  Future<void> _analyze({required bool manual}) async {
    if (_analysing) {
      if (!manual) {
        _pendingAutomaticAnalysis = true;
      }
      return;
    }
    _analysing = true;
    // Hoisted out of the `try` so the refusal below can say what it was about:
    // a failed analysis has to offer the way out of the batch it refused, and
    // that batch is only named inside the block that read it.
    ChatUiSnapshot? current;
    try {
      final ChatUiSnapshot? read = await _readTree();
      // ADR-0022 decision 18: an analysis reads the batch the user reviewed,
      // not a fresh read of the same screen. Re-reading here would answer about
      // an unreviewed copy of what was confirmed, and for a batch the domain
      // refuses that copy is refused the same way — so the confirmation would
      // be thrown away by the very next analysis. A new read still wins as soon
      // as the platform pushes one, because [_acceptSnapshot] replaces
      // [_latest] and clears the flag with it.
      final bool confirmed = _latest?.reviewed ?? false;
      current = confirmed ? _latest : (read ?? _latest);
      _sourceOfCurrent = read != null && identical(current, read)
          ? 'accessibility'
          : _latestSource;
      if (current == null || current.lines.isEmpty) {
        _publish(note: _note(CopyKey.runtimeNoConversation));
        return;
      }
      _latest = current;
      final bool hadAdvice = _advice != null;
      _advice = null;
      _analysedSnapshot = null;
      if (hadAdvice) {
        onAdvice?.call(null);
      }
      _publish(
        analysed: current.conversation,
        live: current.conversation,
        note: _note(CopyKey.runtimeAnalysing),
        reviewing: false,
      );
      final ModelSettings settings = await ModelSettings.load(
        capabilities.preferences,
        capabilities.secretStore,
      );
      if (_customAnalyzer == null && !settings.isReady) {
        _publish(
          analysed: current.conversation,
          live: current.conversation,
          note: _note(CopyKey.runtimeConfigureModels),
        );
        return;
      }
      final Advice result = await (_customAnalyzer ?? _analyzeDomain)(
        current,
        settings,
      );
      _analysedSnapshot = current;
      _advice = result;
      onAdvice?.call(result);
      _publish(
        analysed: current.conversation,
        live: _latest?.conversation ?? current.conversation,
        advice: result,
        note: _caveat(current.note),
      );
    } on DomainException catch (error) {
      _publish(note: PanelNote(error.message, remedy: _refusalRemedy(current)));
    } on Object {
      _publish(note: _note(CopyKey.runtimeAnalysisFailed));
    } finally {
      _analysing = false;
      if (_pendingAutomaticAnalysis) {
        _pendingAutomaticAnalysis = false;
        unawaited(_analyze(manual: false));
      }
    }
  }

  /// The way out of the one refusal that has one (ADR-0022 decision 13).
  ///
  /// Asked with the domain's own predicate rather than by matching the sentence:
  /// `checkAnalysable` refuses for two reasons and the other one is a background
  /// that is too long, which no review can fix. This is the same function the
  /// gate called, over the same lines it was called with, so the two cannot
  /// disagree about which refusal this is.
  PanelRemedy? _refusalRemedy(ChatUiSnapshot? refused) =>
      refused != null && allLinesUnconfirmed(_snapshotOf(refused).transcript)
          ? const EnterReview()
          : null;

  /// The batch as the domain's own snapshot, built in the one place the two
  /// halves meet.
  ///
  /// The analysis hands this to the model and [_refusalRemedy] asks the gate
  /// what it would say about the same lines, so the two must not be built
  /// twice: [_refusalRemedy] used to render the transcript itself, which left it
  /// marking a *confirmed* batch as unconfirmed and offering 「去核对」 for a
  /// batch the user had already confirmed (ADR-0024).
  Snapshot _snapshotOf(ChatUiSnapshot input) => Snapshot.fromCaptured(
    title: input.conversation.title,
    source: _sourceOfCurrent,
    lines: _capturedLines(input.lines),
    reviewed: input.reviewed,
  );

  /// A batch as the domain's own line shape.
  ///
  /// One implementation for every caller, because they all depend on the same
  /// provenance rule: [_snapshotOf] is the only door these lines go through, and
  /// the domain decides what the marker means from there (ADR-0024).
  List<CapturedLine> _capturedLines(List<ChatLine> lines) => <CapturedLine>[
    for (final ChatLine line in lines)
      CapturedLine(
        speaker: line.speaker,
        text: line.text,
        // A photographed line is neither unscored nor trustworthy. The
        // domain reads a null confidence as "not from OCR" and a non-finite
        // one as below the threshold, and the second is the truth here: ML
        // Kit's Chinese recogniser reports no per-line score at all, so the
        // engine cannot vouch for this text and must not be made to.
        confidence: _sourceOfCurrent == 'ocr' ? double.nan : null,
      ),
  ];

  Future<Advice> _analyzeDomain(
    ChatUiSnapshot input,
    ModelSettings settings,
  ) async {
    final SharedMaterial material = _material ??= await SharedMaterial.load(
      capabilities.sharedPayload,
    );
    final Snapshot snapshot = _snapshotOf(input);
    final Profile profile =
        Profile.empty(
              id: input.conversation.toString(),
              label: input.conversation.title ?? '',
            )
            .withValue('goal', settings.goal)
            .withValue('background', settings.relationshipBackground);
    final String scene = material.vocabulary.relationship.sceneFor(
      profile.goal,
    );
    final ReplyPreferences preferences = material.vocabulary.reply.resolve(
      tone: settings.tone,
      length: settings.length,
      count: settings.candidateCount,
    );
    final StrategyRoute? strategyRoute = switch (settings.strategyProvider) {
      StrategyProvider.none => null,
      StrategyProvider.jev => StrategyRoute(
        engine: StrategyEngine.jev,
        model: settings.strategyModel,
      ),
      StrategyProvider.deepseek => StrategyRoute(
        engine: StrategyEngine.deepseek,
        model: settings.strategyModel,
      ),
    };
    final ConfiguredModelTransport transport = ConfiguredModelTransport(
      settings,
      copy: copy,
    );
    try {
      return await analyzeSnapshot(
        transport: transport,
        material: material,
        snapshot: snapshot,
        scene: scene,
        background: buildBackground(
          profile: profile,
          snapshotText: snapshot.transcript,
        ),
        replyModel: settings.replyModel,
        strategyRoute: strategyRoute,
        preferences: preferences,
      );
    } finally {
      transport.close();
    }
  }

  Future<void> _copy(String? text) async {
    if (text == null || text.isEmpty) {
      return;
    }
    await clipboardWrite(text);
    _publish(note: _note(CopyKey.runtimeCopied));
  }

  Future<void> _fill(String? text) async {
    final ChatUiSnapshot? analysed = _analysedSnapshot;
    if (text == null || text.isEmpty || analysed == null) {
      return;
    }
    // Null on the ports with no node tree, and that is the honest answer for
    // them: «the screen has not changed» cannot be established by re-reading
    // something that cannot be re-read, and filling a reply into a conversation
    // nobody verified is worse than declining. The null takes the branch below
    // and the reply is not filled.
    final ChatUiSnapshot? current = await _readTree();
    if (current == null ||
        current.conversation != analysed.conversation ||
        current.signature() != analysed.signature()) {
      _publish(
        live: current?.conversation ?? _latest?.conversation,
        note: _note(CopyKey.runtimeConversationChanged),
      );
      return;
    }
    final String? target = await capabilities.screenCapture.findTargetWindow();
    if (target == null) {
      _publish(note: _note(CopyKey.runtimeConversationChanged));
      return;
    }
    final InjectResult result = await capabilities.textInject.inject(
      text,
      target: InjectTarget(windowId: target),
    );
    if (result.verifiedLanding && result.observedText == text) {
      _publish(note: _note(CopyKey.runtimeFilled));
      return;
    }
    await clipboardWrite(text);
    _publish(note: _note(CopyKey.runtimeFillUnverified));
  }

  void _publish({
    ConversationRef? analysed,
    ConversationRef? live,
    Advice? advice,
    PanelNote? note,
    List<PanelLine>? transcript,
    bool? reviewing,
  }) {
    final PanelFrame current = panel.current;
    panel.publish(
      PanelFrame(
        analysed: analysed ?? current.analysed,
        live: live ?? _latest?.conversation ?? current.live,
        advice: advice ?? _advice,
        note: note,
        transcript: transcript ?? current.transcript,
        appNames: current.appNames,
        reviewing: reviewing ?? current.reviewing,
      ),
    );
  }

  /// A note that is only words, which is nearly all of them.
  ///
  /// The frame carries a [PanelNote] rather than a string since ADR-0021: one
  /// note has a way out of it and has to name the permission it is for, and a
  /// type that can carry a remedy is the only shape that lets the panel draw a
  /// button without the panel knowing which system page it is. The notes that
  /// carry nothing stay one line at the call site because of this.
  PanelNote _note(CopyKey key) => PanelNote(copy.text(key));

  /// A snapshot's own caveat, as the panel takes it.
  ///
  /// Never a remedy: this is what the snapshot says about how it was produced —
  /// "this one was read off a screenshot, check the sides" — and that is
  /// something to read before filling a reply in, not a permission to grant.
  PanelNote? _caveat(String? note) => note == null ? null : PanelNote(note);

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _snapshotSubscription?.cancel();
    await _commandSubscription?.cancel();
  }
}
