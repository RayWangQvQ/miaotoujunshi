import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

/// The runtime's decisions, asked directly (ADR-0011).
///
/// The application's own suite drives the same engine through the shell, with a
/// device double and a real panel session, and that is where the flows are
/// pinned end to end. This file is the other half: the transitions the shell
/// cannot reach without a device configured a particular way — a round deferred
/// rather than dropped, an unconfigured application refused, a refusal whose
/// remedy depends on what the user already confirmed, an event with no words
/// arriving mid-review. Those are one `apply` each and no concurrency, which is
/// the whole reason the machine is synchronous and the effects are a list.
///
/// No capability double appears here, and that is the point rather than a
/// convenience: the engine reaches no capability, so there is nothing to double.
void main() {
  const ConversationRef conversation = ConversationRef(
    packageName: 'com.tencent.mm',
    title: '张三',
  );
  final CaptureFrame frame = CaptureFrame(
    pixels: Uint8List(0),
    width: 1080,
    height: 2400,
    scaleX: 1,
    scaleY: 1,
    originX: 0,
    originY: 0,
  );

  /// Two lines off one screen, one on each side: the user's on the right, the
  /// other party's on the left.
  const List<OcrLine> twoSidedScreen = <OcrLine>[
    OcrLine(
      text: '在吗',
      bounds: ScreenRect(left: 700, top: 700, right: 900, bottom: 740),
      confidence: 1,
    ),
    OcrLine(
      text: '在的',
      bounds: ScreenRect(left: 40, top: 900, right: 240, bottom: 940),
      confidence: 1,
    ),
  ];

  group('the start', () {
    test('asks for one read, and only one', () {
      final ConversationEngine engine = ConversationEngine();

      expect(kinds(engine.apply(const Started())), <Type>[ReadTree]);
      expect(engine.state.analysed, ConversationRef.none);
      expect(engine.state.live, isNull);
    });

    test('a reader that answered nothing publishes nothing', () {
      // The port that refuses the node tree outright (ADR-0009 decision 2). A
      // refusal is a statement about the platform rather than a failure, and the
      // empty state already says what to do — a note here would name a failure
      // that did not happen.
      final ConversationEngine engine = ConversationEngine();

      expect(engine.apply(const TreeAnswered(TreeReadPurpose.start)), isEmpty);
      expect(engine.state.note, isNull);
    });

    test('a reader that threw says there is no conversation', () {
      final ConversationEngine engine = ConversationEngine();

      expect(
        engine.apply(const TreeAnswered(TreeReadPurpose.start, threw: true)),
        isEmpty,
      );
      expect(engine.state.note, const CopyNote(NoteCode.noConversation));
    });
  });

  group('a pushed read', () {
    test('moves the conversation and offers an automatic round', () {
      final ConversationEngine engine = ConversationEngine();

      expect(
        kinds(engine.apply(SnapshotPushed(snapshot('在吗')))),
        <Type>[LoadAutoAnalyseSetting],
      );
      expect(engine.state.live, conversation);
      expect(engine.state.transcript, hasLength(1));
      expect(
        engine.state.analysed,
        conversation,
        reason:
            'before the first analysis the header still names the pushed '
            'conversation instead of showing the unidentified placeholder',
      );
    });

    test('a re-read of the same screen does not offer a round', () {
      // A model call is not free and the signature is the port's own answer to
      // "has this conversation moved on".
      final ConversationEngine engine = ConversationEngine();
      final ChatUiSnapshot read = snapshot('在吗');

      engine.apply(SnapshotPushed(read));

      expect(engine.apply(SnapshotPushed(read)), isEmpty);
    });

    test('a read with no words moves the conversation and nothing else', () {
      // Android's `AndroidConversationEvent`: it fires when the foreground flips
      // and carries no lines at all. The batch being reviewed is still the batch
      // on the screen.
      final ConversationEngine engine = ConversationEngine();
      engine.apply(SnapshotPushed(snapshot('在吗')));
      engine.apply(const CommandReceived(ConversationCommandKind.openReview));
      final ConversationNote? before = engine.state.note;

      expect(
        engine.apply(
          SnapshotPushed(
            ChatUiSnapshot(
              conversation: conversation,
              lines: const <ChatLine>[],
              capturedAt: DateTime.utc(2025, 1, 2),
            ),
          ),
        ),
        isEmpty,
      );
      expect(engine.state.reviewing, isTrue);
      expect(
        engine.state.transcript.map((ChatLine line) => line.text),
        <String>['在吗'],
      );
      expect(engine.state.note, before);
    });

    test('carries the platform\'s own caveat through as somebody else\'s words', () {
      final ConversationEngine engine = ConversationEngine();

      engine.apply(SnapshotPushed(snapshot('在吗', note: 'sides guessed')));

      expect(engine.state.note, const LiteralNote('sides guessed'));
    });
  });

  group('a round', () {
    test('the user asking twice runs once, and nothing is left pending', () {
      // The panel is visibly working and the button is doing the thing; a second
      // press is the user confirming that, not a request for a second round.
      final ConversationEngine engine = ConversationEngine();

      expect(
        kinds(engine.apply(const CommandReceived(ConversationCommandKind.reanalyse))),
        <Type>[ReadTree],
      );
      expect(
        engine.apply(const CommandReceived(ConversationCommandKind.reanalyse)),
        isEmpty,
      );
      expect(engine.state.pendingAutomaticAnalysis, isFalse);
    });

    test('an automatic round arriving mid-round is deferred, not dropped', () {
      // The user pressed nothing, so dropping it would lose the read that
      // triggered it.
      final ConversationEngine engine = ConversationEngine();
      engine.apply(SnapshotPushed(snapshot('一')));
      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
      engine.apply(TreeAnswered(TreeReadPurpose.analysis, snapshot: snapshot('一')));

      expect(engine.apply(const AutoAnalyseRead(true)), isEmpty);
      expect(
        engine.state.pendingAutomaticAnalysis,
        isTrue,
        reason: 'the round in flight has to finish before the new one starts',
      );

      expect(
        kinds(engine.apply(AnalysisSucceeded(advice()))),
        <Type>[EmitAdvice, ReadTree],
        reason: 'a round that ended with one waiting starts it',
      );
      expect(engine.state.pendingAutomaticAnalysis, isFalse);
    });

    test('an unconfigured application is told to configure itself', () {
      final ConversationEngine engine = ConversationEngine();
      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
      engine.apply(TreeAnswered(TreeReadPurpose.analysis, snapshot: snapshot('在吗')));

      expect(engine.apply(RoundSettingsRead(ModelSettings.defaults())), isEmpty);
      expect(engine.state.note, const CopyNote(NoteCode.configureModels));
      expect(engine.state.round, isNull);
    });

    test('a caller with its own round runner is not refused for a model', () {
      // There is no wire to configure, so refusing would be about a model
      // nobody is going to call.
      final ConversationEngine engine = ConversationEngine(
        requiresConfiguredModels: false,
      );
      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
      engine.apply(TreeAnswered(TreeReadPurpose.analysis, snapshot: snapshot('在吗')));

      expect(
        kinds(engine.apply(RoundSettingsRead(ModelSettings.defaults()))),
        <Type>[RunRound],
      );
    });

    test('a round that cannot read the tree is a failed round', () {
      final ConversationEngine engine = ConversationEngine();
      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));

      expect(
        engine.apply(const TreeAnswered(TreeReadPurpose.analysis, threw: true)),
        isEmpty,
      );
      expect(
        engine.state.note,
        const CopyNote(NoteCode.analysisFailed),
        reason: 'a reader that threw is not an empty conversation',
      );
    });

    test('a round with nothing to read says there is no conversation', () {
      final ConversationEngine engine = ConversationEngine();
      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));

      expect(
        engine.apply(const TreeAnswered(TreeReadPurpose.analysis)),
        isEmpty,
      );
      expect(engine.state.note, const CopyNote(NoteCode.noConversation));
    });

    test('an analysis reads the batch the user confirmed, not a fresh read', () {
      // ADR-0022 decision 18, and the reason a confirmation is not thrown away
      // by the very next analysis.
      final ConversationEngine engine = ConversationEngine();
      engine.apply(SnapshotPushed(snapshot('在吗')));
      engine.apply(
        const CommandReceived(
          ConversationCommandKind.confirmTranscript,
          lines: <ChatLine>[ChatLine(speaker: Speaker.me, text: '在吗')],
        ),
      );

      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));

      final TreeAnswered answered = TreeAnswered(
        TreeReadPurpose.analysis,
        snapshot: snapshot('在吗'),
      );
      expect(kinds(engine.apply(answered)), <Type>[LoadRoundSettings]);
      expect(
        engine.state.transcript.single.speaker,
        Speaker.me,
        reason: "the user's speaker survives a re-read of the same screen",
      );
    });

    test('and the confirmation\'s caveat survives the round it fed', () {
      // The caveat is about the batch, not about the round, so a round that
      // reads a confirmed batch has to keep it. It was lost once, and no test
      // noticed: the batch was rebuilt from its own snapshot to pick up the
      // read's provenance, and the snapshot does not carry the note — it cannot,
      // because a note is copy and this package holds none.
      final ConversationEngine engine = ConversationEngine(
        requiresConfiguredModels: false,
      );
      engine.apply(SnapshotPushed(snapshot('在吗')));
      engine.apply(
        const CommandReceived(
          ConversationCommandKind.confirmTranscript,
          lines: <ChatLine>[ChatLine(speaker: Speaker.me, text: '在吗')],
        ),
      );
      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
      engine.apply(TreeAnswered(TreeReadPurpose.analysis));
      engine.apply(RoundSettingsRead(ModelSettings.defaults()));

      expect(engine.apply(AnalysisSucceeded(advice())), isNotEmpty);

      expect(
        engine.state.note,
        const CopyNote(NoteCode.reviewed),
        reason: 'the round answers about the batch a person read, so what the '
            'panel says about that batch is still true when it finishes',
      );
    });
  });

  group('a refusal', () {
    test('a batch nobody has confirmed carries the way into the review', () {
      // ADR-0022 decision 13: this is the refusal a review can fix.
      final ConversationEngine engine = ConversationEngine(
        requiresConfiguredModels: false,
      );
      captureInto(engine, frame, twoSidedScreen);

      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
      engine.apply(const TreeAnswered(TreeReadPurpose.analysis));

      expect(engine.apply(const AnalysisRefused('当前对话全部待核对')), isEmpty);
      expect(
        engine.state.note,
        const LiteralNote('当前对话全部待核对', remedy: AskReview()),
      );
    });

    test('a batch the user has confirmed does not ask to be confirmed again', () {
      // ADR-0024. The remedy is decided by asking the gate what it would say
      // about the lines being analysed, and the runtime used to render those
      // lines itself — which kept the marker on a batch the user had just
      // confirmed, and offered 「去核对」 for a refusal no review can fix.
      final ConversationEngine engine = ConversationEngine(
        requiresConfiguredModels: false,
      );
      captureInto(engine, frame, twoSidedScreen);
      engine.apply(
        const CommandReceived(
          ConversationCommandKind.confirmTranscript,
          lines: <ChatLine>[
            ChatLine(speaker: Speaker.me, text: '在吗'),
            ChatLine(speaker: Speaker.me, text: '在的'),
          ],
        ),
      );

      engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
      engine.apply(const TreeAnswered(TreeReadPurpose.analysis));
      engine.apply(const AnalysisRefused('关系背景过长'));

      expect(engine.state.note, const LiteralNote('关系背景过长'));
      expect(
        engine.state.note!.remedy,
        isNull,
        reason: 'a review cannot shorten a background, and this batch has '
            'already been through one',
      );
    });
  });

  group('the whole-frame capture', () {
    test('a second capture while one is running is not taken', () {
      final ConversationEngine engine = ConversationEngine();

      expect(
        kinds(engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce))),
        <Type>[CaptureScreen],
      );
      expect(
        engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce)),
        isEmpty,
      );
      expect(engine.state.note, const CopyNote(NoteCode.recognising));
    });

    test('a refused frame carries the platform\'s sentence and no remedy', () {
      final ConversationEngine engine = ConversationEngine();
      engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce));

      expect(engine.apply(const CaptureRefused('window is protected')), isEmpty);
      expect(
        engine.state.note,
        const CopyNote(
          NoteCode.captureRefused,
          reason: 'window is protected',
        ),
      );
      expect(engine.state.recognising, isFalse);
    });

    test('an absent accessibility service is named, and carries the page', () {
      final ConversationEngine engine = ConversationEngine();
      engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce));

      expect(
        engine.apply(
          const CaptureThrew(code: ConversationEngine.captureServiceUnavailable),
        ),
        isEmpty,
      );
      expect(
        engine.state.note,
        const CopyNote(
          NoteCode.captureServiceOff,
          remedy: AskPermission(PermissionKind.accessibility),
        ),
      );
    });

    test('any other platform code keeps the generic sentence', () {
      // The bridge's messages are written for a developer. Only the one that has
      // a remedy of its own is spelled out, because a defect has no page to
      // open.
      final ConversationEngine engine = ConversationEngine();
      engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce));

      engine.apply(const CaptureThrew(code: 'android_control_capture_failed'));

      expect(engine.state.note, const CopyNote(NoteCode.captureFailed));
      expect(engine.state.note!.remedy, isNull);
    });

    test('a read frame goes straight into the review', () {
      // ADR-0022 decision 7: every line of a capture carries the marker, so the
      // gate would refuse the first analysis of this batch every time.
      final ConversationEngine engine = ConversationEngine();

      captureInto(engine, frame, twoSidedScreen);

      expect(engine.state.reviewing, isTrue);
      expect(engine.state.latest!.source, capturedByCapture);
      expect(
        engine.state.transcript.map((ChatLine line) => line.speaker),
        <Speaker>[Speaker.me, Speaker.other],
      );
    });

    test('a frame that read nothing says so and leaves the batch alone', () {
      final ConversationEngine engine = ConversationEngine();

      engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce));
      engine.apply(FrameCaptured(frame));

      expect(
        engine.apply(
          LinesRecognised(
            frame: frame,
            lines: const <OcrLine>[],
            at: DateTime.utc(2025),
          ),
        ),
        isEmpty,
      );
      expect(engine.state.note, const CopyNote(NoteCode.nothingRecognised));
      expect(engine.state.latest, isNull);
    });
  });

  group('the review', () {
    test("the user's batch replaces the reading and keeps its provenance", () {
      // ADR-0022 decision 4: a batch read off a screenshot is still a batch read
      // off a screenshot after a person has corrected it.
      final ConversationEngine engine = ConversationEngine();
      captureInto(engine, frame, twoSidedScreen);

      expect(
        engine.apply(
          const CommandReceived(
            ConversationCommandKind.confirmTranscript,
            lines: <ChatLine>[
              ChatLine(speaker: Speaker.me, text: '在吗'),
              ChatLine(speaker: Speaker.me, text: '在的'),
            ],
          ),
        ),
        isEmpty,
      );

      expect(engine.state.reviewing, isFalse);
      expect(engine.state.latest!.source, capturedByCapture);
      expect(engine.state.latest!.snapshot.reviewed, isTrue);
      expect(engine.state.note, const CopyNote(NoteCode.reviewed));
      expect(
        engine.state.transcript.map((ChatLine line) => line.speaker),
        <Speaker>[Speaker.me, Speaker.me],
      );
    });

    test('an empty confirmation changes nothing', () {
      final ConversationEngine engine = ConversationEngine();
      captureInto(engine, frame, twoSidedScreen);
      final ConversationNote? before = engine.state.note;

      expect(
        engine.apply(
          const CommandReceived(
            ConversationCommandKind.confirmTranscript,
            lines: <ChatLine>[ChatLine(speaker: Speaker.me, text: '   ')],
          ),
        ),
        isEmpty,
      );
      expect(engine.state.reviewing, isTrue);
      expect(engine.state.note, before);
    });

    test('dropping the batch drops it, and clears the caveat with it', () {
      final ConversationEngine engine = ConversationEngine();
      captureInto(engine, frame, twoSidedScreen);

      expect(
        engine.apply(const CommandReceived(ConversationCommandKind.cancelReview)),
        isEmpty,
      );
      expect(engine.state.latest, isNull);
      expect(engine.state.analysed, ConversationRef.none);
      expect(engine.state.transcript, isEmpty);
      expect(
        engine.state.note,
        isNull,
        reason: 'the note asked about sides that are no longer on the panel',
      );
    });

    test('a review with nothing to review says so', () {
      final ConversationEngine engine = ConversationEngine();

      expect(
        engine.apply(const CommandReceived(ConversationCommandKind.openReview)),
        isEmpty,
      );
      expect(engine.state.note, const CopyNote(NoteCode.noConversation));
    });
  });

  group('the fill', () {
    test('is three steps, and ends on the clipboard when the landing is unseen', () {
      final ConversationEngine engine = analysed(ready());

      expect(
        kinds(
          engine.apply(
            const CommandReceived(ConversationCommandKind.fill, text: '好呀'),
          ),
        ),
        <Type>[ReadTree],
      );
      expect(
        kinds(engine.apply(TreeAnswered(TreeReadPurpose.fill, snapshot: snapshot('在吗')))),
        <Type>[FindFillTarget],
      );

      final List<ConversationEffect> injecting = engine.apply(
        const FillTargetResolved('7'),
      );
      final InjectText inject = injecting.single as InjectText;
      expect(inject.windowId, '7');
      expect(inject.text, '好呀');

      final List<ConversationEffect> fallback = engine.apply(
        const InjectionResolved(false),
      );
      expect(
        (fallback.single as WriteClipboard).text,
        '好呀',
        reason: 'a landing nobody saw is answered with the clipboard, not a '
            'second injection into a conversation nobody has verified',
      );
      expect(engine.state.note, const CopyNote(NoteCode.fillUnverified));
    });

    test('a verified landing says so and writes nothing', () {
      final ConversationEngine engine = analysed(ready());
      engine.apply(const CommandReceived(ConversationCommandKind.fill, text: '好呀'));
      engine.apply(TreeAnswered(TreeReadPurpose.fill, snapshot: snapshot('在吗')));
      engine.apply(const FillTargetResolved('7'));

      expect(engine.apply(const InjectionResolved(true)), isEmpty);
      expect(engine.state.note, const CopyNote(NoteCode.filled));
    });

    test('the conversation moving on stops the fill before it writes', () {
      final ConversationEngine engine = analysed(ready());
      engine.apply(const CommandReceived(ConversationCommandKind.fill, text: '好呀'));

      expect(
        engine.apply(
          TreeAnswered(TreeReadPurpose.fill, snapshot: snapshot('改天吧')),
        ),
        isEmpty,
      );
      expect(engine.state.note, const CopyNote(NoteCode.conversationChanged));
      expect(engine.state.fill, isNull);
    });

    test('a port with no tree to re-read refuses the fill', () {
      // Nothing to re-read means «the screen has not changed» cannot be
      // established, and filling into a conversation nobody verified is worse
      // than declining.
      final ConversationEngine engine = analysed(ready());
      engine.apply(const CommandReceived(ConversationCommandKind.fill, text: '好呀'));

      expect(engine.apply(const TreeAnswered(TreeReadPurpose.fill)), isEmpty);
      expect(engine.state.note, const CopyNote(NoteCode.conversationChanged));
    });

    test('with nothing analysed there is nothing to fill', () {
      final ConversationEngine engine = ConversationEngine();

      expect(
        engine.apply(
          const CommandReceived(ConversationCommandKind.fill, text: '好呀'),
        ),
        isEmpty,
      );
      expect(engine.state.note, isNull);
    });
  });

  group('copy', () {
    test('puts the text on the clipboard and says so', () {
      final ConversationEngine engine = ConversationEngine();

      final List<ConversationEffect> effects = engine.apply(
        const CommandReceived(ConversationCommandKind.copy, text: '好呀'),
      );

      expect((effects.single as WriteClipboard).text, '好呀');
      expect(engine.state.note, const CopyNote(NoteCode.copied));
    });

    test('an empty draft is not a copy', () {
      final ConversationEngine engine = ConversationEngine();

      expect(
        engine.apply(const CommandReceived(ConversationCommandKind.copy, text: '')),
        isEmpty,
      );
      expect(engine.state.note, isNull);
    });
  });

  group('leaving service', () {
    test('a disposed engine answers nothing, including its own commands', () {
      final ConversationEngine engine = ConversationEngine();
      engine.apply(SnapshotPushed(snapshot('在吗')));

      expect(engine.apply(const EngineDisposed()), isEmpty);
      expect(
        engine.apply(const CommandReceived(ConversationCommandKind.reanalyse)),
        isEmpty,
      );
      expect(engine.apply(SnapshotPushed(snapshot('在吗'))), isEmpty);
      expect(
        engine.state.note,
        isNull,
        reason: 'a disposed engine does not write notes either',
      );
    });
  });
}

/// The effect types of one step, in order.
///
/// The effects carry no `==` on purpose — two `ReadTree(analysis)` calls are the
/// same request, and a test that says so by comparing values would be pinning an
/// accident of the order they are listed in. What a test wants to know is the
/// shape of the sequence, and then the payload of the one it cares about.
List<Type> kinds(List<ConversationEffect> effects) => <Type>[
  for (final ConversationEffect effect in effects) effect.runtimeType,
];

ChatUiSnapshot snapshot(String text, {bool reviewed = false, String? note}) =>
    ChatUiSnapshot(
      conversation: const ConversationRef(
        packageName: 'com.tencent.mm',
        title: '张三',
      ),
      lines: <ChatLine>[ChatLine(speaker: Speaker.other, text: text)],
      capturedAt: DateTime.utc(2025),
      reviewed: reviewed,
      note: note,
    );

/// Settings that can run a round, and the same settings that cannot.
ModelSettings ready() => ModelSettings.defaults().copyWith(replyKey: 'secret');

/// Drives a whole-frame capture through to the review state.
void captureInto(
  ConversationEngine engine,
  CaptureFrame frame,
  List<OcrLine> lines,
) {
  engine.apply(const CommandReceived(ConversationCommandKind.recogniseOnce));
  engine.apply(FrameCaptured(frame));
  engine.apply(
    LinesRecognised(frame: frame, lines: lines, at: DateTime.utc(2025)),
  );
}

/// An engine that has already analysed one batch, which is what a fill needs.
ConversationEngine analysed(ModelSettings settings) {
  final ConversationEngine engine = ConversationEngine(
    requiresConfiguredModels: false,
  );
  engine.apply(SnapshotPushed(snapshot('在吗')));
  engine.apply(const CommandReceived(ConversationCommandKind.reanalyse));
  engine.apply(
    TreeAnswered(TreeReadPurpose.analysis, snapshot: snapshot('在吗')),
  );
  engine.apply(RoundSettingsRead(settings));
  engine.apply(AnalysisSucceeded(advice()));
  return engine;
}

Advice advice() => Advice(
  support: 'support',
  facts: const <String>['fact'],
  hypotheses: const <String>[],
  unknowns: const <String>[],
  intent: 'intent',
  intentConfidence: 0.8,
  strategy: '澄清',
  recommendation: 'recommendation',
  nextStep: 'next',
  stopCondition: 'stop',
  question: 'question',
  candidates: <Candidate>[
    Candidate(text: '好呀', reason: 'reason', tradeoff: 'tradeoff', weight: 100),
  ],
  rankingStatus: RankingStatus.single,
);
