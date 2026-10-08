import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import '../panel/protocol.dart';
import '../panel/session.dart';
import '../panel/translation.dart';
import 'model_transport.dart';

/// How one round is run when a test substitutes for the model.
///
/// The seam is two arguments wide on purpose. A round is a snapshot and the
/// settings, and everything else about it — the provenance of the lines, the
/// scene, the background, the strategy route — is resolved from those two by the
/// domain, so a caller that swaps the whole round does not have to reproduce any
/// of it.
typedef ConversationAnalyzer =
    Future<Advice> Function(ChatUiSnapshot snapshot, ModelSettings settings);

/// The imperative half of the runtime: it runs the effects, and decides nothing.
///
/// Every question the runtime answers — what the panel is showing, whether a
/// second round is refused or deferred, whether this refusal carries a way out,
/// whether an event with no words ends a review — is in [ConversationEngine]
/// (ADR-0009 decision 3: the platform owns *when*, the domain owns *what*). What
/// is left here is the part that cannot be anywhere else: the awaits, the
/// platform's own exceptions, and the two translations — the engine's note codes
/// into copy, and the engine's state into the frame the panel is fed.
///
/// **The state is not published, it is read.** After every [ConversationEngine.
/// apply], this file translates the state into a [PanelFrame] and pushes it. So
/// there is no such thing as a change the engine forgot to announce, and no
/// effect vocabulary for frame publishing.
final class ConversationRuntime {
  ConversationRuntime({
    required this.capabilities,
    required this.panel,
    required this.copy,
    required this.clipboardWrite,
    this.onAdvice,
    ConversationAnalyzer? analyzer,
  }) : _customAnalyzer = analyzer,
       // A substituted round never reaches a wire, so there is no model to
       // configure and refusing an unconfigured application would be refusing
       // about something nobody is going to call.
       _engine = ConversationEngine(requiresConfiguredModels: analyzer == null);

  final CapabilitySet capabilities;
  final PanelSession panel;
  final AppCopy copy;
  final FutureOr<void> Function(String text) clipboardWrite;
  final ValueChanged<Advice?>? onAdvice;
  final ConversationAnalyzer? _customAnalyzer;
  final ConversationEngine _engine;

  /// The payload, read once. Every scene and every vocabulary entry comes out of
  /// it, and none of it changes while the application runs.
  SharedMaterial? _material;

  StreamSubscription<ChatUiSnapshot>? _snapshotSubscription;
  StreamSubscription<PanelCommand>? _commandSubscription;

  Future<void> start() async {
    _snapshotSubscription = _subscribeToPushedReads();
    _commandSubscription = panel.commands.listen(_handleCommand);
    await _dispatch(const Started());
  }

  Future<void> dispose() async {
    // Applied rather than dispatched: the engine has to stop answering, and
    // there is no frame to publish for it — a final republish on the way out is
    // a push at a panel whose session may already be closed.
    _engine.apply(const EngineDisposed());
    await _snapshotSubscription?.cancel();
    await _commandSubscription?.cancel();
  }

  void _handleCommand(PanelCommand command) =>
      unawaited(_dispatch(commandOf(command)));

  /// One event in, its effects run, and the frame republished.
  ///
  /// Recursive rather than iterative, and that is the "one step at a time" rule
  /// made literal: an effect comes back as one event, that event is applied, and
  /// only then does the next effect of the batch run. A loop would let two
  /// effects of one batch both be in flight before either had been answered,
  /// which is exactly the state the engine's own guards are written to avoid.
  Future<void> _dispatch(ConversationEvent event) async {
    final List<ConversationEffect> effects = _engine.apply(event);
    _publishFrame();
    for (final ConversationEffect effect in effects) {
      final ConversationEvent? next = await _run(effect);
      if (next == null) {
        continue;
      }
      await _dispatch(next);
    }
  }

  /// Runs one effect and answers with what to tell the engine, or null when
  /// there is nothing to report.
  Future<ConversationEvent?> _run(ConversationEffect effect) async {
    switch (effect) {
      case ReadTree(:final TreeReadPurpose purpose):
        return _readTree(purpose);

      case CaptureScreen():
        return _captureScreen();

      case RecogniseFrame(:final CaptureFrame frame):
        return _recognise(frame);

      case LoadAutoAnalyseSetting():
        final ModelSettings settings = await _loadSettings();
        return AutoAnalyseRead(settings.autoAnalyze);

      // The read that decides whether a round may run at all. A failure here is
      // the round failing: there is nothing to publish about a settings store
      // that will not answer, and the note that says so is the round's own.
      case LoadRoundSettings():
        try {
          return RoundSettingsRead(await _loadSettings());
        } on Object {
          return const AnalysisFailed();
        }

      case RunRound(
        :final ChatUiSnapshot snapshot,
        :final String source,
        :final ModelSettings settings,
      ):
        return _runRound(snapshot, source, settings);

      case EmitAdvice(:final Advice? advice):
        onAdvice?.call(advice);
        return null;

      // A failure is swallowed, and deliberately rather than by omission: the
      // panel that asked is the only surface that could report it, it asked
      // *because* it is stuck, and turning a failed jump into a second note
      // would replace one dead end with another. The settings section reads the
      // same state and is the surface that can say the jump did not happen.
      case OpenPermissionSettings(:final PermissionKind kind):
        try {
          await capabilities.permissions.openSettings(kind);
        } on Object {
          // Nothing to do with it here — see the note above.
        }
        return null;

      case WriteClipboard(:final String text):
        await clipboardWrite(text);
        return null;

      case FindFillTarget():
        return FillTargetResolved(
          await capabilities.screenCapture.findTargetWindow(),
        );

      case InjectText(:final String windowId, :final String text):
        return _inject(windowId, text);

      case PersistIdentity(
        :final String title,
        :final String packageName,
        :final String appName,
        :final List<ChatLine> lines,
      ):
        await _persistIdentity(title, packageName, appName, lines);
        return null;
    }
  }

  /// Reads one snapshot, telling a refusal apart from a defect.
  ///
  /// [UiTreeReader] is the member Android answers and the two desktop ports
  /// refuse (ADR-0009 decision 2): macOS and Windows read pixels and recover the
  /// words through OCR, so there is no node tree to ask for and — permanently,
  /// not for this milestone — never will be. The refusal is a statement about
  /// the platform rather than a failure, and turning it into "no snapshot" is
  /// what lets the rest of the runtime keep asking one question, «what is on
  /// screen», instead of branching on the port at every call site.
  ///
  /// `on UnsupportedError` catches the narrower `UnimplementedError` with it,
  /// which is the SDK's own hierarchy and not an oversight — a not-yet is an
  /// `UnsupportedError` too. Both mean the same thing here, «ask the capture
  /// path instead», so they share one clause; where the two must be told apart
  /// `askCapability` is the one that does it.
  ///
  /// **Nothing that is not the typed refusal is swallowed.** A reader that is
  /// broken rather than refusing is reported as [TreeAnswered.threw], so a crash
  /// and a desktop port stay distinguishable — the engine decides what each of
  /// the three reads does about it.
  Future<ConversationEvent> _readTree(TreeReadPurpose purpose) async {
    try {
      return TreeAnswered(
        purpose,
        snapshot: await capabilities.uiTreeReader.readActiveChat(),
      );
    } on UnsupportedError {
      return TreeAnswered(purpose);
    } on Object {
      return TreeAnswered(purpose, threw: true);
    }
  }

  /// The platform pushing a reading of the screen, on the ports that push one.
  ///
  /// Same refusal, same answer as [_readTree], and for the same reason: a port
  /// with no node tree has no stream to subscribe to. Null rather than an empty
  /// stream is the point — an empty stream is a live-looking thing that will
  /// never speak, which is exactly the shape ADR-0009 forbids an implementation
  /// to answer with. Here the caller is the one deciding, and "this port does
  /// not push" is a fact the engine already handles: without a pushed read, the
  /// batch in play is the one a capture produced.
  StreamSubscription<ChatUiSnapshot>? _subscribeToPushedReads() {
    try {
      return capabilities.uiTreeReader.snapshots.listen(
        (ChatUiSnapshot snapshot) =>
            unawaited(_dispatch(SnapshotPushed(snapshot))),
        onError: (_) => unawaited(_dispatch(const SnapshotStreamFailed())),
      );
    } on UnsupportedError {
      return null;
    }
  }

  /// Photographs whatever is in front. The composition and the reasons it is
  /// composed this way are in [ConversationEngine]; this is only the call.
  Future<ConversationEvent> _captureScreen() async {
    try {
      return switch (await capabilities.screenCapture.capture()) {
        // The platform's own words for a frame it refused: Android's
        // `ScreenCapture` writes them to be shown unchanged — they name the
        // cause and, where there is one, the remedy — and `CaptureFailed.code`
        // is deliberately untranslated, so passing the sentence through keeps
        // both the taxonomy and the advice.
        CaptureFailed(:final String message) => CaptureRefused(message),
        CaptureOk(:final CaptureFrame frame) => FrameCaptured(frame),
      };
    } on PlatformException catch (failure) {
      // The one place in the three ports that raises this code is Android's
      // bridge, when its accessibility service is off. The code and not the
      // message: the message is written for a developer.
      return CaptureThrew(code: failure.code);
    } on Object {
      // The platform declining to answer at all — a channel that is gone, a
      // bridge that never attached — rather than declining this particular
      // frame.
      return const CaptureThrew();
    }
  }

  /// Reads the frame. A frame we could not take and a frame we could not read
  /// are two different notes, which is why this is its own step.
  Future<ConversationEvent> _recognise(CaptureFrame frame) async {
    try {
      return LinesRecognised(
        frame: frame,
        lines: await capabilities.ocr.recognize(
          frame,
          languages: const <String>['zh-Hans'],
        ),
        // The caller's clock, not the domain's: the moment the platform
        // answered is a fact about this process.
        at: DateTime.now(),
      );
    } on Object {
      return const RecognitionFailed();
    }
  }

  Future<ConversationEvent> _runRound(
    ChatUiSnapshot snapshot,
    String source,
    ModelSettings settings,
  ) async {
    try {
      final ConversationAnalyzer? custom = _customAnalyzer;
      final Advice advice = custom != null
          ? await custom(snapshot, settings)
          : await _analyzeDomain(snapshot, source, settings);
      return AnalysisSucceeded(advice);
    } on DomainException catch (error) {
      // The domain's own refusal, in its own sentence. Which of its two reasons
      // it is decides whether there is a way out, and that is the engine's call
      // — it holds the batch the gate refused.
      return AnalysisRefused(error.message);
    } on Object {
      return const AnalysisFailed();
    }
  }

  /// One round against the real model.
  ///
  /// The transport is built here and closed here, which is what keeps the
  /// network, the credentials and the redirect policy out of the domain while
  /// still letting [analyzeConfigured] run the whole judgement. [copy] travels
  /// with it because the transport's own failures are sentences a person reads.
  ///
  /// [source] is passed rather than looked up: it is how the lines being
  /// analysed were obtained, the engine knows it, and a round that re-derived it
  /// could disagree with the batch's own provenance.
  Future<Advice> _analyzeDomain(
    ChatUiSnapshot input,
    String source,
    ModelSettings settings,
  ) async {
    final SharedMaterial material =
        _material ??= await SharedMaterial.load(capabilities.sharedPayload);
    final ConfiguredModelTransport transport = ConfiguredModelTransport(
      settings,
      copy: copy,
    );
    try {
      return await analyzeConfigured(
        transport: transport,
        material: material,
        snapshot: snapshotOf(
          title: input.conversation.title,
          lines: input.lines,
          source: source,
          reviewed: input.reviewed,
        ),
        settings: settings,
      );
    } finally {
      transport.close();
    }
  }

  Future<ConversationEvent> _inject(String windowId, String text) async {
    final InjectResult result = await capabilities.textInject.inject(
      text,
      target: InjectTarget(windowId: windowId),
    );
    return InjectionResolved(
      result.verifiedLanding && result.observedText == text,
    );
  }

  /// Writes the identity a review confirmed into the knowledge base (ADR-0030).
  ///
  /// The person half becomes a contact, merged by name rather than duplicated;
  /// an application name entered with no package behind it is stored under the
  /// name itself as the key. Both are best-effort: a store that will not answer
  /// must not turn a successful confirmation into a failure, because the
  /// analysis that follows does not read these — they are for the next time.
  ///
  /// The confirmed lines are appended to that contact's history so the knowledge
  /// base can later show the conversation, not just who the person is.
  Future<void> _persistIdentity(
    String title,
    String packageName,
    String appName,
    List<ChatLine> lines,
  ) async {
    if (title.trim().isNotEmpty) {
      try {
        final List<KnowledgeContact> existing =
            await capabilities.knowledgeStore.contacts();
        final KnowledgeContact contact = contactForName(
          existing: existing,
          name: title,
          packageName: packageName,
          appName: appName,
          now: DateTime.now(),
        );
        await capabilities.knowledgeStore.saveContact(contact);
        if (lines.isNotEmpty) {
          await capabilities.knowledgeStore.appendLog(
            contact.id,
            <KnowledgeLogEntry>[
              for (final ChatLine line in lines)
                KnowledgeLogEntry(
                  speaker: line.speaker,
                  text: line.text,
                  timestamp: DateTime.now(),
                  packageName: packageName,
                ),
            ],
          );
        }
      } on Object {
        // The contact is a convenience for the next session, not this round.
      }
    }
    if (packageName.trim().isEmpty && appName.trim().isNotEmpty) {
      try {
        await capabilities.knowledgeStore.saveAppName(
          appName.trim(),
          appName.trim(),
        );
      } on Object {
        // Same as above.
      }
    }
  }

  Future<ModelSettings> _loadSettings() => ModelSettings.load(
    capabilities.preferences,
    capabilities.secretStore,
    goal: copy.text(CopyKey.settingsGoalDefault),
  );

  /// The state, as the panel is fed it.
  ///
  /// A straight translation of seven fields, and nothing is added to it: the
  /// app's display name used to ride beside the frame in a map the panel
  /// resolved against, and nothing ever filled that map on any port — so the
  /// header could not name an application at all (ADR-0018, settled by
  /// ADR-0028). The name travels on the reference now, where the platform that
  /// resolved it put it.
  void _publishFrame() {
    final ConversationState state = _engine.state;
    panel.publish(
      PanelFrame(
        analysed: state.analysed,
        live: state.live,
        advice: state.advice,
        note: state.note == null ? null : noteOf(state.note!, copy),
        transcript: <PanelLine>[
          for (final ChatLine line in state.transcript)
            PanelLine(speaker: line.speaker, text: line.text),
        ],
        reviewing: state.reviewing,
      ),
    );
  }
}
