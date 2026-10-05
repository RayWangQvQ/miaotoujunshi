import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/runtime/model_settings.dart';
import 'package:miaotou_app/src/runtime/model_transport.dart';
import 'package:miaotou_domain/miaotou_domain.dart';

void main() {
  late HttpServer server;
  late Uri base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://${server.address.host}:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('chat sends the selected route and decodes content and logprobs', () async {
    final Future<void> response = server.first.then((HttpRequest request) async {
      expect(request.uri.path, '/v1/chat/completions');
      expect(request.headers.value(HttpHeaders.authorizationHeader), 'Bearer secret');
      final Map<String, Object?> body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>;
      expect(body['model'], 'reply-model');
      expect(body['logprobs'], isTrue);
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': 'A'},
                'logprobs': <String, Object?>{
                  'content': <Object?>[
                    <String, Object?>{
                      'token': 'A',
                      'top_logprobs': <Object?>[
                        <String, Object?>{'token': 'A', 'logprob': -0.1},
                        <String, Object?>{'token': 'B', 'logprob': -2.0},
                      ],
                    },
                  ],
                },
              },
            ],
          }),
        );
      await request.response.close();
    });
    final ModelSettings settings = ModelSettings.defaults.copyWith(
      replyBaseUrl: '$base/v1',
      replyModel: 'reply-model',
      replyKey: 'secret',
    );
    final ConfiguredModelTransport transport = ConfiguredModelTransport(
      settings,
      copy: AppCopy.zh,
    );

    final ChatCompletion completion = await transport.chat(
      ChatRoute.reply,
      const ChatRequest(
        model: 'reply-model',
        choiceLogprobs: true,
        messages: <ChatMessage>[ChatMessage.user('hello')],
      ),
    );

    expect(completion.content, 'A');
    expect(completion.logprobs?.firstToken, 'A');
    expect(
      completion.logprobs?.top.map((TopLogprob item) => item.token),
      <String>['A', 'B'],
    );
    await response;
    transport.close();
  });

  test('provider error bodies never escape into the domain error', () async {
    const String sensitive = 'echoed private chat and bearer token';
    final Future<void> response = server.first.then((HttpRequest request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write(sensitive);
      await request.response.close();
    });
    final ConfiguredModelTransport transport = ConfiguredModelTransport(
      ModelSettings.defaults.copyWith(
        replyBaseUrl: '$base/v1',
        replyKey: 'secret',
      ),
      copy: AppCopy.zh,
    );

    await expectLater(
      transport.chat(
        ChatRoute.reply,
        const ChatRequest(
          model: 'reply-model',
          messages: <ChatMessage>[ChatMessage.user('hello')],
        ),
      ),
      throwsA(
        isA<DomainException>().having(
          (DomainException error) => error.message,
          'message',
          allOf(contains('401'), isNot(contains(sensitive))),
        ),
      ),
    );
    await response;
    transport.close();
  });
}
