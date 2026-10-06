import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

/// The panel's identity and read-only rules, ported from ADR-0002 — which was
/// written against Android because Android was the only port that had the
/// problem. The expectations below are Android's own, from
/// `ConversationRefTest.kt` and `ChatModels.displayLabel()`, so a unification
/// that drops one of them goes red here rather than on a device.
///
/// ADR-0026 revised the fallback: an app with no resolved display name now
/// shows its package name rather than a placeholder, so a header is never empty
/// while a window is in front. Only NONE (no window) drops to the placeholder.
void main() {
  const ConversationRef qq = ConversationRef(packageName: 'com.tencent.mobileqq');
  const ConversationRef wechat = ConversationRef(packageName: 'com.tencent.mm');
  const ConversationRef stranger = ConversationRef(packageName: 'com.example.unknown');

  /// Android's `ChatApps.displayName`: null is a real answer, not a failure.
  String? appName(ConversationRef reference) => <String, String>{
        'com.tencent.mobileqq': 'QQ',
        'com.tencent.mm': '微信',
      }[reference.packageName];

  Advice adviceWith(List<Candidate> candidates) => Advice(
        support: '.',
        facts: const <String>['x'],
        hypotheses: const <String>[],
        unknowns: const <String>[],
        intent: null,
        intentConfidence: null,
        strategy: '降压',
        recommendation: '.',
        nextStep: '.',
        stopCondition: '.',
        question: '',
        candidates: candidates,
      );

  final Candidate one = const Candidate(text: '好', reason: '.', tradeoff: '.');

  group('naming a conversation', () {
    test('both halves known', () {
      final ConversationLabel label = ConversationLabel.of(
        const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        appName: '微信',
      );
      expect(label.kind, ConversationLabelKind.appAndTitle);
      expect(label.appName, '微信');
      expect(label.title, '张三');
      expect(label.isIdentified, isTrue);
    });

    test('the thread is named and the app falls back to its package', () {
      // ADR-0026: an app with no resolved name is still named by its package, so
      // a named thread shows `app · title` with the package as the app half.
      final ConversationLabel label = ConversationLabel.of(
        const ConversationRef(packageName: 'com.example.unknown', title: '张三'),
      );
      expect(label.kind, ConversationLabelKind.appAndTitle);
      expect(label.appName, 'com.example.unknown');
      expect(label.title, '张三');
    });

    test('a title with no package at all is title-only', () {
      // The one case titleOnly survives: a title was read but even the package
      // is unknown (NONE carries no title, so this is a synthetic edge).
      final ConversationLabel label = ConversationLabel.of(
        const ConversationRef(packageName: '', title: '张三'),
      );
      expect(label.kind, ConversationLabelKind.titleOnly);
      expect(label.appName, isNull);
      expect(label.title, '张三');
    });

    test('the app is named but the title could not be read', () {
      // Android's own case: `QQ · 未知应用`.
      final ConversationLabel label = ConversationLabel.of(qq, appName: appName(qq));
      expect(label.kind, ConversationLabelKind.appOnly);
      expect(label.appName, 'QQ');
      expect(label.title, isNull);
      expect(label.isIdentified, isFalse);
    });

    test('a blank title counts as no title', () {
      // Android: `ConversationRef("com.tencent.mobileqq", "   ")` is the same as
      // a null title — a transient placeholder is not a name anyone can confirm
      // a fill against.
      final ConversationLabel label = ConversationLabel.of(
        const ConversationRef(packageName: 'com.tencent.mobileqq', title: '   '),
        appName: 'QQ',
      );
      expect(label.kind, ConversationLabelKind.appOnly);
      expect(label.title, isNull);
    });

    test('neither half known falls back to the package, then the placeholder', () {
      // ADR-0026: an app with no resolved name still shows its package name, so
      // the header is never empty while a window is in front. Only when even the
      // package is unknown (NONE) does it drop to the placeholder.
      final ConversationLabel label = ConversationLabel.of(stranger);
      expect(label.kind, ConversationLabelKind.appOnly);
      expect(label.appName, 'com.example.unknown',
          reason: 'with no resolved name, the package name names the app');
      expect(label.title, isNull);
    });

    test('nothing at all known is the placeholder', () {
      // Android: `ConversationRef("", null)` (NONE) is 「未知应用」 — the one case
      // left after the package fallback.
      final ConversationLabel label =
          ConversationLabel.of(const ConversationRef(packageName: ''));
      expect(label.kind, ConversationLabelKind.unrecognised);
      expect(label.appName, isNull);
      expect(label.title, isNull);
    });
  });

  group('the read-only derivation', () {
    test('the analysed conversation is the one in front of the user', () {
      final PanelView view = derivePanel(
        analysed: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        live: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        advice: adviceWith(<Candidate>[one]),
        appName: appName,
      );
      expect(view.status, PanelStatus.viewing);
      expect(view.readOnly, isFalse);
      expect(view.allows(PanelAction.fill), isTrue);
      expect(view.allows(PanelAction.copy), isTrue);
      expect(view.allows(PanelAction.details), isTrue);
      expect(view.allows(PanelAction.reanalyse), isTrue);
    });

    test('the user moved on: fill is withdrawn, copy and detail are not', () {
      // ADR-0002 decision 3, and the divergence it corrects: Windows'
      // `set_available(false)` disables fill, copy and reason together.
      final PanelView view = derivePanel(
        analysed: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        live: const ConversationRef(packageName: 'com.tencent.mobileqq', title: '李四'),
        advice: adviceWith(<Candidate>[one]),
        appName: appName,
      );
      expect(view.status, PanelStatus.browsingReadOnly);
      expect(view.readOnly, isTrue);
      expect(view.allows(PanelAction.fill), isFalse,
          reason: 'filling a candidate into a conversation that was not the one '
              'analysed is the mis-fill ADR-0002 exists to prevent');
      expect(view.allows(PanelAction.copy), isTrue,
          reason: 'the drafts are still useful; ADR-0002 revokes fill only');
      expect(view.allows(PanelAction.details), isTrue);
    });

    test('read-only replaces reanalyse with analyse-current', () {
      // ADR-0002 decision 3 again: the old 「重新分析」 reused the snapshot on
      // the panel, which while read-only belongs to another conversation, so
      // tapping it silently did nothing.
      final PanelView whenCurrent = derivePanel(
        analysed: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        live: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        advice: adviceWith(<Candidate>[one]),
        appName: appName,
      );
      final PanelView whenBrowsing = derivePanel(
        analysed: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        live: const ConversationRef(packageName: 'com.tencent.mobileqq', title: '李四'),
        advice: adviceWith(<Candidate>[one]),
        appName: appName,
      );
      expect(whenCurrent.allows(PanelAction.reanalyse), isTrue);
      expect(whenCurrent.allows(PanelAction.analyseCurrent), isFalse);
      expect(whenBrowsing.allows(PanelAction.reanalyse), isFalse);
      expect(whenBrowsing.allows(PanelAction.analyseCurrent), isTrue);
    });

    test('nothing analysed yet', () {
      final PanelView view = derivePanel(
        analysed: null,
        live: wechat,
        advice: null,
        appName: appName,
      );
      expect(view.status, PanelStatus.notAnalysed);
      expect(view.readOnly, isFalse,
          reason: 'read-only is "showing an old conversation"; with no analysis '
              'there is nothing to be stale');
      expect(view.actions, <PanelAction>{PanelAction.reanalyse},
          reason: 'with no drafts there is nothing to copy, fill or open');
    });

    test('a fill needs a named thread, even when it is the current one', () {
      // macOS gates fill on having read a title; Android's fillInput re-reads
      // the tree and compares title and signature. Both say the same thing: a
      // fill writes into a specific thread, so we have to know which.
      final PanelView view = derivePanel(
        analysed: wechat,
        live: wechat,
        advice: adviceWith(<Candidate>[one]),
        appName: appName,
      );
      expect(view.analysed.kind, ConversationLabelKind.appOnly);
      expect(view.allows(PanelAction.fill), isFalse);
      expect(view.allows(PanelAction.copy), isTrue,
          reason: 'an unnamed thread may still be worth copying from; only '
              'writing into it is unsafe');
    });

    test('no drafts means nothing to fill even when everything matches', () {
      final PanelView view = derivePanel(
        analysed: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        live: const ConversationRef(packageName: 'com.tencent.mm', title: '张三'),
        advice: adviceWith(const <Candidate>[]),
        appName: appName,
      );
      expect(view.allows(PanelAction.fill), isFalse);
      expect(view.allows(PanelAction.copy), isTrue,
          reason: '"本轮建议不回复" is an analysis with no drafts, and its detail '
              'is still worth opening');
    });

    test('the note travels with the view', () {
      final PanelView view = derivePanel(
        analysed: wechat,
        live: wechat,
        advice: null,
        appName: appName,
        note: 'OCR 无法判断说话人',
      );
      expect(view.note, 'OCR 无法判断说话人');
    });
  });

  group('conversation identity', () {
    List<CapturedLine> lines(List<String> texts) => <CapturedLine>[
          for (final String text in texts)
            CapturedLine(speaker: Speaker.other, text: text),
        ];

    test('the last six lines, as wire tokens', () {
      // Ported from ChatSnapshot.signature(): `takeLast(6)`, `side:text`.
      final String signature = conversationSignature(lines(<String>[
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
      ]));
      expect(signature, 'other:c|other:d|other:e|other:f|other:g|other:h');
    });

    test('the speaker is the wire token, not the display word', () {
      // speakerLabel(Speaker.other) is 对方, and a redesign could reword it. A
      // signature that changes when somebody rewords a label is not a
      // signature.
      final String signature = conversationSignature(<CapturedLine>[
        const CapturedLine(speaker: Speaker.me, text: 'x'),
        const CapturedLine(speaker: Speaker.other, text: 'y'),
      ]);
      expect(signature, 'me:x|other:y');
      expect(signature, isNot(contains('对方')));
    });

    test('one new message moves it', () {
      final List<CapturedLine> before = lines(<String>['a', 'b', 'c']);
      final List<CapturedLine> after = <CapturedLine>[
        ...before,
        const CapturedLine(speaker: Speaker.other, text: 'd'),
      ];
      expect(conversationSignature(after), isNot(conversationSignature(before)));
    });

    test('a pasted transcript has no signature', () {
      // Identity is a property of what was read. An empty signature is not a
      // valid identity to compare against, which is the point of leaving it
      // empty rather than hashing the pasted text.
      expect(Snapshot(title: 'a', transcript: '对方：忙。').signature, isEmpty);
    });

    test('a captured snapshot carries one', () {
      final Snapshot snapshot = Snapshot.fromCaptured(
        title: '张三',
        lines: lines(<String>['a', 'b']),
      );
      expect(snapshot.signature, 'other:a|other:b');
    });
  });
}
