import 'dart:convert';

import 'package:miaotou_domain/miaotou_domain.dart';

/// One recorded chat call.
final class RecordedChat {
  RecordedChat(this.route, this.request);

  final ChatRoute route;
  final ChatRequest request;

  /// The decoded user payload, which is what most assertions are about.
  Map<String, Object?> get payload {
    final ChatMessage user = request.messages.last;
    return (jsonDecode(user.content) as Map).cast<String, Object?>();
  }

  String get system => request.messages.first.content;
}

/// A [ModelTransport] driven by a script, so the whole pipeline can be run with
/// no socket, no key and no clock.
///
/// Each chat call consumes the next scripted answer. An answer may be a [String]
/// (plain content), a [ChatCompletion] (content with or without logprobs) or a
/// [DomainException] (a scripted failure). The queue is deliberately exhausted
/// into an error rather than a default: a test that under-scripts its transport
/// should see the call count it actually made.
final class FakeTransport implements ModelTransport {
  FakeTransport({List<Object>? chatAnswers, this.systemoneAnswer = '{}'})
      : chatAnswers = <Object>[...?chatAnswers];

  final List<Object> chatAnswers;
  String systemoneAnswer;

  final List<RecordedChat> chats = <RecordedChat>[];
  final List<Map<String, Object?>> systemoneCalls = <Map<String, Object?>>[];

  int _next = 0;

  @override
  Future<ChatCompletion> chat(ChatRoute route, ChatRequest request) async {
    chats.add(RecordedChat(route, request));
    if (_next >= chatAnswers.length) {
      throw DomainException(
        'the fake transport was asked for chat call ${chats.length} but was '
        'scripted with ${chatAnswers.length}',
      );
    }
    final Object answer = chatAnswers[_next++];
    return switch (answer) {
      ChatCompletion() => answer,
      String() => ChatCompletion(answer),
      DomainException() => throw answer,
      _ => throw StateError('unsupported scripted answer: $answer'),
    };
  }

  @override
  Future<String> systemone(Map<String, Object?> payload) async {
    systemoneCalls.add(payload);
    return systemoneAnswer;
  }
}

/// A chat completion carrying a first-token logprob set.
ChatCompletion choice(String content, List<(String, double)> top) =>
    ChatCompletion(
      content,
      logprobs: Logprobs(
        firstToken: content,
        top: <TopLogprob>[
          for (final (String token, double logprob) in top)
            TopLogprob(token, logprob),
        ],
      ),
    );

/// The seven rotated-choice answers every strategy distribution test needs: each
/// rotation picks [winner] through the label map it was actually given.
///
/// It reads the prompt rather than assuming the rotation, which is what makes the
/// test fail when the rotation is wrong instead of when the model is.
List<Object> rotationAnswers({
  required String winner,
  required List<String> strategies,
  required List<int> rotations,
  required List<String> labels,
  double preferred = -0.2,
  double other = -3.0,
}) {
  final List<Object> answers = <Object>[];
  for (final int offset in rotations) {
    final Map<String, String> mapping = <String, String>{
      for (int i = 0; i < labels.length; i++)
        labels[i]: strategies[(i + offset) % strategies.length],
    };
    final String selected = mapping.entries
        .firstWhere((MapEntry<String, String> entry) => entry.value == winner)
        .key;
    answers.add(choice(
      selected,
      <(String, double)>[
        for (final String label in labels)
          (label, label == selected ? preferred : other),
      ],
    ));
  }
  return answers;
}

/// Decodes a JSON object, widened for the assertions that read a payload back.
Map<String, Object?> decodeObject(String raw) =>
    (jsonDecode(raw) as Map).cast<String, Object?>();
