/// The one thing in this package that reaches outside it, and how it is kept
/// out of the package anyway.
///
/// The deciding half has to ask three things of a model: draft a reply, decide a
/// strategy, and answer the judge questions. All three are network calls, and
/// `miaotou_domain` may not import `dart:io` (ADR-0009) — so the calls cannot
/// happen here at all. Instead the domain *declares* what it needs and the
/// application supplies it. The dependency points inwards, which is the whole
/// trick: the logic stays a pure function of its inputs, and its tests run with
/// no socket, no key and no clock.
///
/// **This is not an eleventh capability.** ADR-0009 fixes the platform contract
/// at ten interfaces, and every one of them is a thing one platform can do and
/// another cannot — a window, a keystroke, a keychain. An HTTPS request is not:
/// Dart does it identically on all three ports, so there is nothing for a
/// platform package to answer. Putting it behind the contract would make all
/// three ports write the same HTTP client and answer for a member none of them
/// differ on. It belongs to the application, behind this port.
library;

/// Which configured route a chat request travels.
///
/// Two routes rather than one, because the ports let the strategy decision and
/// the reply drafting point at different providers with different credentials —
/// and the domain must not be the thing that knows a base URL. The application
/// maps each value onto whatever it configured.
enum ChatRoute {
  /// The reply model: drafts the candidates.
  reply,

  /// The DeepSeek strategy route, including its rotated first-token requests.
  strategy,
}

/// One message of a chat request.
final class ChatMessage {
  const ChatMessage.system(this.content) : role = 'system';

  const ChatMessage.user(this.content) : role = 'user';

  const ChatMessage(this.role, this.content);

  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{'role': role, 'content': content};

  @override
  String toString() => 'ChatMessage($role, ${content.length} chars)';
}

/// One chat completion request.
///
/// It carries the flags that change how the provider must be *asked* rather than
/// what is asked, so that the transport can set `response_format`, `logprobs`
/// and the token budget without the domain knowing a provider's field names.
final class ChatRequest {
  const ChatRequest({
    required this.model,
    required this.messages,
    this.jsonMode = false,
    this.choiceLogprobs = false,
  });

  final String model;
  final List<ChatMessage> messages;

  /// Ask the provider to constrain the output to one JSON object.
  final bool jsonMode;

  /// Ask for the first output token's twenty best alternatives. This is what
  /// makes a seven-way label distribution possible at all, and it is only
  /// available on some routes — the transport refuses when it is not, rather
  /// than sending a request that would come back without them.
  final bool choiceLogprobs;

  @override
  String toString() =>
      'ChatRequest($model, ${messages.length} messages, json=$jsonMode, '
      'logprobs=$choiceLogprobs)';
}

/// One entry of a first token's alternatives.
final class TopLogprob {
  const TopLogprob(this.token, this.logprob);

  final String token;
  final double logprob;

  @override
  String toString() => 'TopLogprob($token, $logprob)';
}

/// The first output token and the alternatives the provider reported for it.
final class Logprobs {
  const Logprobs({required this.firstToken, required this.top});

  /// The token that was actually emitted, as the provider spells it. Compared
  /// against the returned content so that a later token can never be mistaken
  /// for the choice.
  final String? firstToken;

  final List<TopLogprob> top;
}

/// What one chat request came back with.
final class ChatCompletion {
  const ChatCompletion(this.content, {this.logprobs});

  final String content;

  /// Non-null only when the request asked for logprobs.
  final Logprobs? logprobs;

  @override
  String toString() => 'ChatCompletion(${content.length} chars, '
      'logprobs=${logprobs == null ? 'none' : logprobs!.top.length})';
}

/// The outbound port, implemented by the application and faked by the tests.
///
/// Two members because there are two provider shapes. The chat shape is
/// OpenAI-compatible and serves both the reply model and the DeepSeek strategy
/// route; the `systemone` shape is TypeSafe's judging endpoint, which takes a
/// payload of questions and answers them together.
///
/// **The transport owns credentials, base URLs, timeouts and redirect policy.**
/// Those are the parts the three ports genuinely do differently, and the parts
/// that must never be logged next to a snapshot. It also owns the provider's
/// failure text: an HTTP body may echo the user's chat or a bearer token, so the
/// existing ports deliberately never show it, and nothing here asks them to.
abstract interface class ModelTransport {
  /// One chat completion on [route].
  ///
  /// Throws a `DomainException` when the provider failed, the response was not a
  /// chat completion, or the content came back empty — the domain treats all
  /// three as one refusal and never fabricates a substitute.
  Future<ChatCompletion> chat(ChatRoute route, ChatRequest request);

  /// One TypeSafe judging request, returning the **raw response body**.
  ///
  /// The body is not decoded here. Decoding it is the difference between "the
  /// service did not answer" and "the service answered something that is not a
  /// strategy", and the second is an interpretation the domain has to make and
  /// report in the product's language. A transport that quietly decoded and
  /// returned `{}` would turn a broken answer into a plausible empty one.
  ///
  /// **Every failure is reported as a [DomainException].** That is the one thing
  /// the transport owes the domain: a refusal shaped the way the rest of the
  /// layer refuses, with a message fit to show. HTTP status, redirect policy,
  /// timeouts and the provider's error body are the transport's business, and the
  /// provider's own text must never travel — it can echo the user's chat or a
  /// bearer token.
  Future<String> systemone(Map<String, Object?> payload);
}
