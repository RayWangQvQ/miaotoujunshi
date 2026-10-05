import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

/// The transcript is the only thing the model reads about the conversation, so
/// its rendering is the whole of "what the model was told". These are the three
/// details that have burned the ports: an unattributable line must not acquire an
/// author, an uncertain OCR line must be marked, and a `NaN` confidence must be
/// treated as worst-case rather than as trustworthy.
void main() {
  group('Snapshot validation', () {
    test('refuses an empty transcript before anything is sent', () {
      expect(
        () => Snapshot(title: 'A', transcript: '   \n  '),
        throwsA(isA<DomainException>().having(
          (DomainException e) => e.message,
          'message',
          '请先读取或粘贴对话',
        )),
      );
    });

    test('accepts exactly the budget and refuses one character past it', () {
      expect(Snapshot(title: 'A', transcript: '字' * maxTranscript).transcript.length,
          maxTranscript);
      expect(
        () => Snapshot(title: 'A', transcript: '字' * (maxTranscript + 1)),
        throwsA(isA<DomainException>().having(
          (DomainException e) => e.message,
          'message',
          contains('12000'),
        )),
      );
    });
  });

  group('transcript rendering', () {
    test('keeps an unattributable line unattributed', () {
      final String transcript = renderTranscript(const <CapturedLine>[
        CapturedLine(speaker: Speaker.me, text: '周六见吗'),
        CapturedLine(speaker: Speaker.other, text: '这周忙'),
        CapturedLine(speaker: Speaker.unknown, text: '嗯'),
      ]);
      expect(transcript, '我：周六见吗\n对方：这周忙\n说话人待确认：嗯');
    });

    test('marks a low-confidence OCR line and leaves a confident one alone', () {
      final String transcript = renderTranscript(const <CapturedLine>[
        CapturedLine(speaker: Speaker.other, text: '这周忙', confidence: .79),
        CapturedLine(speaker: Speaker.other, text: '下周再说', confidence: 1),
        CapturedLine(speaker: Speaker.me, text: '粘贴来的', confidence: null),
      ]);
      expect(transcript, '对方：这周忙 [OCR待核对]\n对方：下周再说\n我：粘贴来的');
    });

    test('treats a non-finite confidence as untrustworthy', () {
      // `NaN < .8` is false, so a naive comparison would wave this through.
      final String transcript = renderTranscript(<CapturedLine>[
        CapturedLine(speaker: Speaker.other, text: '看不清', confidence: double.nan),
      ]);
      expect(transcript, contains('[OCR待核对]'));
    });

    test('shows a sender only when the chat app showed one', () {
      final String transcript = renderTranscript(const <CapturedLine>[
        CapturedLine(speaker: Speaker.other, text: '在吗', sender: '张三'),
        CapturedLine(speaker: Speaker.me, text: '在', sender: ''),
      ]);
      expect(transcript, '对方（张三）：在吗\n我：在');
    });
  });

  group('unconfirmed detection', () {
    test('a transcript of nothing but bad lines is flagged', () {
      expect(allLinesUnconfirmed('说话人待确认：嗯\n对方：好的 [OCR待核对]'), isTrue);
    });

    test('one good line among bad ones is enough to proceed', () {
      expect(allLinesUnconfirmed('说话人待确认：嗯\n对方：这周忙'), isFalse);
    });

    test('any bad line anywhere is enough to distrust the token weights', () {
      expect(transcriptHasUnconfirmed('我：在\n对方：这周忙 [OCR待核对]'), isTrue);
      expect(transcriptHasUnconfirmed('我：在\n对方：这周忙'), isFalse);
    });
  });

  test('fromCaptured trims a missing title to the empty string', () {
    final Snapshot snapshot = Snapshot.fromCaptured(
      title: null,
      lines: const <CapturedLine>[
        CapturedLine(speaker: Speaker.other, text: '在吗'),
      ],
    );
    expect(snapshot.title, '');
    expect(snapshot.source, 'ocr');
    expect(snapshot.transcript, '对方：在吗');
  });
}
