import 'package:miaotou_capabilities/testing.dart';
import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

void main() {
  test('model settings keep credentials out of plain preferences', () async {
    final InMemoryCapabilities capabilities = InMemoryCapabilities();
    final ModelSettings settings = ModelSettings.defaults().copyWith(
      replyBaseUrl: 'https://reply.example/v1',
      replyModel: 'reply-model',
      replyKey: 'reply-secret',
      strategyProvider: StrategyProvider.deepseek,
      strategyBaseUrl: 'https://strategy.example/v1',
      strategyModel: 'strategy-model',
      strategyKey: 'strategy-secret',
      autoAnalyze: true,
      relationshipBackground: 'trusted background',
    );

    await settings.save(
      capabilities.preferences,
      capabilities.secretStore,
    );
    final ModelSettings restored = await ModelSettings.load(
      capabilities.preferences,
      capabilities.secretStore,
    );

    expect(restored, settings);
    expect(
      capabilities.preferences.values.values,
      isNot(contains(anyOf('reply-secret', 'strategy-secret'))),
    );
    expect(
      capabilities.secretStore.secrets,
      <String, String>{
        ModelSettings.replySecretKey: 'reply-secret',
        ModelSettings.strategySecretKey: 'strategy-secret',
      },
    );
  });

  test('endpoint assembly accepts a base ending at v1', () {
    final ModelSettings settings = ModelSettings.defaults().copyWith(
      replyBaseUrl: 'https://reply.example/v1/',
      strategyBaseUrl: 'https://strategy.example/',
    );

    expect(
      settings.replyEndpoint,
      Uri.parse('https://reply.example/v1/chat/completions'),
    );
    expect(
      settings.strategyChatEndpoint,
      Uri.parse('https://strategy.example/chat/completions'),
    );
    expect(
      settings.systemoneEndpoint,
      Uri.parse('https://strategy.example/v1/systemone'),
    );
  });
}
