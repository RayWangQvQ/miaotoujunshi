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
/// **No `identity` field yet.** The old ports hash the transcript to reject a
/// stale response; that hash is conversation identity, and #12 owns it — see the
/// package doc. Adding it here would put a `sha256` dependency in the domain for
/// the sake of a field nothing in this milestone reads.
final class Snapshot {
  Snapshot({
    required this.title,
    required this.transcript,
    this.windowId = 0,
    this.source = 'manual',
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
  factory Snapshot.fromCaptured({
    required String? title,
    required List<CapturedLine> lines,
    int windowId = 0,
    String source = 'ocr',
  }) =>
      Snapshot(
        title: (title ?? '').trim(),
        transcript: renderTranscript(lines),
        windowId: windowId,
        source: source,
      );

  final String title;

  /// The conversation as text, one line per message.
  final String transcript;

  /// The window this was read from. Zero when it was not read from a window.
  final int windowId;

  /// How the transcript was obtained. It travels to the model, which is told to
  /// weigh a pasted transcript differently from a machine-read one.
  final String source;
}

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
