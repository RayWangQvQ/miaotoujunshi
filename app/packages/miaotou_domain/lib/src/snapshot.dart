import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'errors.dart';

/// The transcript budget, in characters. Past this the request is refused rather
/// than truncated: a silently cut conversation would let the model answer a
/// question the user did not ask.
const int maxTranscript = 12000;

/// Below this OCR confidence a line is marked `[OCR待核对]`.
///
/// The line is still shown — a half-read sentence is often still usable, and
/// hiding it would lose the turn entirely — but it is marked so that both the
/// user and the model can discount it.
const double ocrConfidenceThreshold = 0.8;

/// One line as the perception layer read it, before it becomes transcript text.
///
/// It exists so that the rendering below has a single input shape. The three
/// ports produce different intermediate types — a macOS dict, an Android
/// `ChatLine`, a Windows tuple — and every one of them has to become the same
/// transcript, because the transcript is what the model reads.
final class CapturedLine {
  const CapturedLine({
    required this.speaker,
    required this.text,
    this.sender,
    this.confidence,
  });

  final Speaker speaker;
  final String text;

  /// A display name the chat application showed for this line, when it showed
  /// one. Null is the normal case in a one-to-one thread.
  final String? sender;

  /// The OCR engine's confidence, when the line came from an image rather than
  /// from an accessibility tree. Null means "not from OCR".
  final double? confidence;
}

/// A conversation as it is about to be analysed.
///
/// The transcript is plain text, not a structure, because that is what the
/// prompt sends and what the user may edit before submitting. Everything else
/// here is identification, and identity is why this type has a validator: an
/// empty or oversized transcript must fail here, before a network call, rather
/// than reach a provider.
///
/// **Identity is [signature], not a hash.** #7 deferred this on the assumption
/// that the old ports hashed the transcript; none of them does. Android is the
/// only port that names the idea, and it compares the title and the last six
/// messages (`ChatSnapshot.signature()`, read by `verifiedInput` before a fill).
/// That is the whole of the identity the ports actually use, so it is what
/// #12 ports — see [conversationSignature]. A hash would have added a crypto
/// dependency to the domain to compute a value nothing compares.
final class Snapshot {
  Snapshot({
    required this.title,
    required this.transcript,
    this.windowId = 0,
    this.source = 'manual',
    this.capturedLines = const <CapturedLine>[],
    this.reviewed = false,
  }) {
    if (transcript.trim().isEmpty) {
      throw const DomainException('请先读取或粘贴对话');
    }
    if (transcript.length > maxTranscript) {
      throw const DomainException('对话过长，请只保留当前问题相关的 12000 字以内内容');
    }
  }

  /// Builds a snapshot out of what the perception layer read.
  ///
  /// The "we could not read the window at all" refusal is **not** here. That is
  /// the platform's failure to report — a null target window, a `CaptureFailed`
  /// — and it is answered at the contract, not by handing the domain an empty
  /// snapshot. What this does own is the shape of every line, which must be one
  /// implementation because the model reads the result.
  ///
  /// The captured lines are kept alongside the rendered transcript so the
  /// anti-injection filter can see which lines came from the other party without
  /// re-parsing the rendered form. They are empty for a pasted transcript, and
  /// an empty list is the filter's no-op signal (#10, AC1).
  /// **A reviewed batch is quoted without the per-line doubt.**
  ///
  /// [reviewed] drops `[OCR待核对]` from the rendered transcript and from
  /// nothing else: [capturedLines] keeps the confidence the recogniser gave, and
  /// [source] still says `ocr`, so the model is still told where the words came
  /// from. What it is no longer told is to doubt every one of them — a person
  /// has just read the batch line by line and corrected it, and the engine is
  /// quoting that person, not the recogniser. A `说话人待确认` line keeps its
  /// label: the user chose *not to* attribute it, which is a different fact
  /// (ADR-0015) and one a review does not erase.
  ///
  /// It was the other way round until ADR-0024. Left as it was, the marker told
  /// the model that every line of a confirmed batch was unvouched-for, and a
  /// model that believes it has nothing trustworthy to answer from answers with
  /// no candidates at all — which the panel then had no way to show.
  factory Snapshot.fromCaptured({
    required String? title,
    required List<CapturedLine> lines,
    int windowId = 0,
    String source = 'ocr',
    bool reviewed = false,
  }) =>
      Snapshot(
        title: (title ?? '').trim(),
        transcript: renderTranscript(reviewed ? _withoutOcrDoubt(lines) : lines),
        windowId: windowId,
        source: source,
        capturedLines: lines,
        reviewed: reviewed,
      );

  final String title;

  /// The conversation as text, one line per message.
  final String transcript;

  /// The window this was read from. Zero when it was not read from a window.
  final int windowId;

  /// How the transcript was obtained. It travels to the model, which is told to
  /// weigh a pasted transcript differently from a machine-read one.
  final String source;

  /// The lines the transcript was rendered from, when it came from capture.
  ///
  /// Empty for a pasted transcript. Carried so the filter
  /// ([sanitizeCandidateTexts]) can read the other party's text directly,
  /// rather than parsing the rendered transcript back into structure — which
  /// would couple the filter to the renderer's exact format.
  final List<CapturedLine> capturedLines;

  /// Whether a person read this batch and confirmed it (ADR-0022).
  ///
  /// It is what [checkAnalysable] reads instead of the per-line markers once it
  /// is set, and it is **not** a claim about the recogniser: [source] still
  /// says `ocr`, because confirming says "this is what the screen said", not
  /// "the recogniser was right".
  ///
  /// It does end the per-line doubt. A confirmed line no longer carries
  /// `[OCR待核对]` into the transcript, because after a review the engine is
  /// quoting the person who read the screen rather than the pixels it read
  /// (ADR-0024).
  final bool reviewed;

  /// A stable signature of the last few lines — this conversation's identity.
  ///
  /// Empty for a pasted transcript, which has no captured lines and therefore no
  /// signature: identity is a property of what was read, and a signature
  /// invented from pasted text would compare equal to nothing.
  String get signature => conversationSignature(capturedLines);
}

/// The same lines with the recogniser's confidence taken off them.
///
/// Only the confidence goes, because that is the one field whose rendering is a
/// claim about whether the engine vouches for the text. The speaker stays,
/// including [Speaker.unknown]: a line the user declined to attribute is
/// answered by `说话人待确认`, which a review confirms rather than resolves.
List<CapturedLine> _withoutOcrDoubt(List<CapturedLine> lines) => <CapturedLine>[
  for (final CapturedLine line in lines)
    CapturedLine(speaker: line.speaker, text: line.text, sender: line.sender),
];

/// The label a speaker is written as in a transcript.
///
/// These are the **display** words, and they are not the wire vocabulary
/// ADR-0015 governs. What the model sees is the finished transcript, so this is
/// the one place the mapping is spelled; nothing above the contract should
/// re-spell it.
String speakerLabel(Speaker speaker) => switch (speaker) {
      Speaker.me => '我',
      Speaker.other => '对方',
      Speaker.unknown => '说话人待确认',
    };

/// Renders captured lines into the transcript the model reads.
///
/// Three details are load-bearing:
///
/// * an unattributable line keeps its `说话人待确认` label instead of being
///   folded into one side — ADR-0015's whole point is that inventing an author
///   is worse than admitting there is none;
/// * an OCR line below [ocrConfidenceThreshold] carries `[OCR待核对]`, so a
///   model that reads a misrecognised character has been told to be careful;
/// * a non-finite confidence is treated as *below* the threshold, because
///   `NaN` compares false against everything and would otherwise pass as
///   trustworthy.
String renderTranscript(List<CapturedLine> lines) => lines.map((CapturedLine line) {
      final String side = speakerLabel(line.speaker);
      final String sender =
          (line.sender == null || line.sender!.isEmpty) ? '' : '（${line.sender}）';
      final double? confidence = line.confidence;
      final bool uncertain = confidence != null &&
          (!confidence.isFinite || confidence < ocrConfidenceThreshold);
      return '$side$sender：${line.text}${uncertain ? ' [OCR待核对]' : ''}';
    }).join('\n');

/// A stable signature of the last few lines, to tell two conversations apart.
///
/// Ported from `ChatSnapshot.signature()`, which Android's fill guard compares
/// alongside the title (`verifiedInput`): the last six messages, each as
/// `speaker:text`, joined.
///
/// **The speaker is written as its wire token, not as [speakerLabel].** A
/// signature is compared across captures, and `speakerLabel` is display copy
/// that a redesign could legitimately reword — a signature that changes when
/// somebody rewords 对方 is not a signature. Six lines is a judgement, not a
/// constant: short enough that one new message moves it, long enough that two
/// threads do not collide by accident.
String conversationSignature(List<CapturedLine> lines) {
  final Iterable<CapturedLine> tail =
      lines.length <= 6 ? lines : lines.sublist(lines.length - 6);
  return tail.map((CapturedLine line) => '${line.speaker.name}:${line.text}').join('|');
}

/// True when this one transcript line is marked as not trustworthy.
bool isUnconfirmedLine(String line) =>
    line.startsWith('说话人待确认') || line.contains('[OCR待核对]');

/// True when any line anywhere in the transcript is unattributed or unverified.
///
/// This is the weaker question, and the strategy step asks it rather than
/// [allLinesUnconfirmed]: a strategy decided from a conversation with some
/// uncertain attribution is still worth having, but its token weights are not,
/// because a rotation over labels cannot be read as stable when the labels
/// themselves are in doubt.
bool transcriptHasUnconfirmed(String transcript) =>
    transcript.contains('说话人待确认') || transcript.contains('[OCR待核对]');

/// True when there is nothing in the transcript worth analysing.
///
/// The refusal is deliberate and it is not "no messages": it fires only when
/// *every* non-blank line is unattributed or unverified. A transcript with one
/// good line and four bad ones is a transcript with evidence in it, and the
/// model is asked to work within that.
bool allLinesUnconfirmed(String transcript) {
  final List<String> lines = transcript
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return false;
  }
  return lines.every(isUnconfirmedLine);
}
