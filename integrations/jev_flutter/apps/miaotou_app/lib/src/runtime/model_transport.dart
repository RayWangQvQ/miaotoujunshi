import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:miaotou_domain/miaotou_domain.dart';

import '../design/copy.dart';
import 'model_settings.dart';

final class ConfiguredModelTransport implements ModelTransport {
  ConfiguredModelTransport(
    this.settings, {
    required this.copy,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ModelSettings settings;
  final AppCopy copy;
  final http.Client _client;

  @override
  Future<ChatCompletion> chat(ChatRoute route, ChatRequest request) async {
    final bool strategy = route == ChatRoute.strategy;
    final Uri endpoint = strategy
        ? settings.strategyChatEndpoint
        : settings.replyEndpoint;
    final String key = strategy ? settings.strategyKey : settings.replyKey;
    final Map<String, Object?> payload = <String, Object?>{
      'model': request.model,
      'messages': <Object?>[
        for (final ChatMessage message in request.messages) message.toJson(),
      ],
      if (request.jsonMode)
        'response_format': <String, Object?>{'type': 'json_object'},
      if (request.choiceLogprobs) ...<String, Object?>{
        'logprobs': true,
        'top_logprobs': 20,
        'max_tokens': 1,
      },
    };
    final String body = await _post(endpoint, key, payload);
    try {
      final Map<String, Object?> root = (jsonDecode(body) as Map)
          .cast<String, Object?>();
      final List<Object?> choices = (root['choices'] as List).cast<Object?>();
      final Map<String, Object?> choice = (choices.first as Map)
          .cast<String, Object?>();
      final Map<String, Object?> message = (choice['message'] as Map)
          .cast<String, Object?>();
      final String content = message['content'] as String;
      if (content.trim().isEmpty) {
        throw const FormatException();
      }
      return ChatCompletion(
        content,
        logprobs: request.choiceLogprobs ? _decodeLogprobs(choice) : null,
      );
    } on Object {
      throw DomainException(copy.text(CopyKey.runtimeInvalidResponse));
    }
  }

  @override
  Future<String> systemone(Map<String, Object?> payload) =>
      _post(settings.systemoneEndpoint, settings.strategyKey, payload);

  Future<String> _post(
    Uri endpoint,
    String key,
    Map<String, Object?> payload,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final http.Request request = http.Request('POST', endpoint)
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json'
          ..headers['Authorization'] = 'Bearer $key';
        if (endpoint.host.toLowerCase().contains('openrouter.ai')) {
          request.headers
            ..['HTTP-Referer'] = 'https://miaotoujunshi.local'
            ..['X-Title'] = 'Miaotou Junshi';
        }
        request.body = jsonEncode(payload);
        final http.StreamedResponse response = await _client
            .send(request)
            .timeout(const Duration(seconds: 40));
        final String body = await response.stream.bytesToString();
        if ((response.statusCode == 429 || response.statusCode == 529) &&
            attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * (1 << attempt)),
          );
          continue;
        }
        if (response.isRedirect ||
            response.statusCode < 200 ||
            response.statusCode >= 300) {
          throw DomainException(
            copy
                .text(CopyKey.runtimeHttpStatus)
                .replaceAll('{status}', '${response.statusCode}'),
          );
        }
        if (body.trim().isEmpty) {
          throw DomainException(copy.text(CopyKey.runtimeInvalidResponse));
        }
        return body;
      } on DomainException {
        rethrow;
      } on Object {
        if (attempt == 2) {
          throw DomainException(copy.text(CopyKey.runtimeNetworkFailure));
        }
      }
    }
    throw DomainException(copy.text(CopyKey.runtimeNetworkFailure));
  }

  Logprobs _decodeLogprobs(Map<String, Object?> choice) {
    final Map<String, Object?> raw = (choice['logprobs'] as Map)
        .cast<String, Object?>();
    final List<Object?> content = (raw['content'] as List).cast<Object?>();
    final Map<String, Object?> first = (content.first as Map)
        .cast<String, Object?>();
    final List<Object?> top = (first['top_logprobs'] as List).cast<Object?>();
    return Logprobs(
      firstToken: first['token'] as String?,
      top: <TopLogprob>[
        for (final Object? item in top)
          TopLogprob(
            (item as Map)['token'] as String,
            (item)['logprob'] as double,
          ),
      ],
    );
  }

  void close() => _client.close();
}
