import 'dart:convert';

import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

import 'support/fake_transport.dart';
import 'support/repo_payload.dart';

/// The four scenes the payload names — 日常回复, 邀约推进, 冲突修复, 投入与退出 —
/// were macOS's exclusive before the migration. The domain already resolves
/// a scene to its material in #7; this test locks the property AC2 needs:
/// the scene the user picks changes what the advice is based on, both the
/// documents and the prompt that carries them.
void main() {
  late SharedMaterial material;
  late List<String> scenes;

  setUpAll(() async {
    material = await loadRealMaterial();
    scenes = material.vocabulary.scenes;
  });

  /// Builds the reply prompt directly, so the assertion can reach the
  /// material paths without coupling this test to the model wire.
  Future<ReplyPrompt> promptFor(String scene) async {
    final SceneMaterial sceneMaterial = await material.scene(scene);
    return buildReplyPrompt(
      snapshot: Snapshot(title: 'A', transcript: '对方：忙，下周再看看吧。'),
      scene: scene,
      background: '',
      material: sceneMaterial,
      vocabulary: material.vocabulary,
    );
  }

  test('the payload declares more than one scene', () {
    expect(scenes.length, greaterThan(1),
        reason: 'if the payload declares only one scene, AC2 is vacuous; '
            'the payload map is the test of the four-scene contract');
  });

  group('the scene the user picks changes what the advice is based on', () {
    test('loads different knowledge documents', () async {
      // Skip-safe: the previous test already asserts scenes.length > 1, so
      // reaching here means two scenes are available to compare.
      final ReplyPrompt one = await promptFor(scenes.first);
      final ReplyPrompt two = await promptFor(scenes[1]);
      expect(
        one.materialPaths.join('|'),
        isNot(equals(two.materialPaths.join('|'))),
        reason: 'different scenes must load different knowledge documents; '
            'a shared knowledge doc would mean the scene choice is cosmetic',
      );
    });

    test('produces prompts whose system block differs', () async {
      final ReplyPrompt one = await promptFor(scenes.first);
      final ReplyPrompt two = await promptFor(scenes[1]);
      expect(
        one.messages.first.content,
        isNot(equals(two.messages.first.content)),
        reason: 'the references are part of the system prompt; if two scenes '
            'produced the same system prompt, the scene is not changing what '
            'the advice is based on',
      );
    });

    test('an unknown scene is refused before any knowledge is loaded', () async {
      // A billed call for an input that was never usable is the failure this
      // ordering exists to prevent — already covered for the analysis path;
      // re-asserted here so the scene contract has its own lock.
      final FakeTransport transport = FakeTransport(
        chatAnswers: <Object>[
          jsonEncode(<String, Object?>{
            'support': '.',
            'facts': <String>['x'],
            'hypotheses': <String>[],
            'unknowns': <String>[],
            'strategy': '降压',
            'recommendation': '.',
            'next_step': '.',
            'stop_condition': '.',
            'question': '',
            'candidates': const <Object?>[],
          }),
        ],
      );
      await expectLater(
        analyzeSnapshot(
          transport: transport,
          material: material,
          snapshot: Snapshot(title: 'A', transcript: '对方：忙。'),
          scene: '不存在',
          background: '',
          replyModel: 'reply-model',
        ),
        throwsA(isA<DomainException>().having(
          (DomainException e) => e.message,
          'message',
          contains('分析场景'),
        )),
      );
      expect(transport.chats, isEmpty);
      expect(transport.systemoneCalls, isEmpty);
    });
  });
}