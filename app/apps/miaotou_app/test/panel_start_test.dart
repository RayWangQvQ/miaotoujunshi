import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/capability_registry.dart';
import 'package:miaotou_app/src/design/copy.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// The four refusal codes `FloatingPanel.show()` raises, and what each means.
///
/// Until ADR-0021 nothing in Dart caught any of them, so declining the overlay
/// permission was an exception out of `main()`: no panel, no sentence, nothing to
/// do next. The mapping is a pure function over four strings and can therefore be
/// pinned here without a device — and it is pinned by a device-side test as well,
/// because the strings themselves are written in Kotlin and nothing else in this
/// repository would notice them being renamed.
void main() {
  const AppCopy copy = AppCopy.zh;

  group('a refused show', () {
    test('a denial names the permission, because the page is the way back', () {
      final PanelNote note = panelShowFailureNote(
        PlatformException(code: 'overlay_permission_denied'),
        copy,
      );

      expect(note.text, copy.text(CopyKey.runtimePanelPermissionDenied));
      expect(
        note.remedy,
        PermissionKind.overlay,
        reason: 'the user was taken to the page and declined; the same page is '
            'still the only thing that fixes it',
      );
    });

    test('a pending request is waited on rather than answered with a jump', () {
      final PanelNote note = panelShowFailureNote(
        PlatformException(code: 'overlay_permission_pending'),
        copy,
      );

      expect(note.text, copy.text(CopyKey.runtimePanelPermissionPending));
      expect(
        note.remedy,
        isNull,
        reason: 'a dialog is already on screen; a button under the sentence '
            'would send the user to a page that is about to answer itself',
      );
    });

    test('a plugin with no activity to ask from offers no page', () {
      final PanelNote note = panelShowFailureNote(
        PlatformException(code: 'overlay_permission_unavailable'),
        copy,
      );

      expect(note.text, copy.text(CopyKey.runtimePanelShowFailed));
      expect(
        note.remedy,
        isNull,
        reason: 'no grant from the user can supply the Activity the plugin is '
            'missing, so this one is a defect and says so in one sentence',
      );
    });

    test('a failed show is one sentence and no remedy', () {
      final PanelNote note = panelShowFailureNote(
        PlatformException(code: 'android_panel_show_failed'),
        copy,
      );

      expect(note.text, copy.text(CopyKey.runtimePanelShowFailed));
      expect(note.remedy, isNull);
    });

    test('an unknown code still says something', () {
      // The generic `android_panel_<method>_failed` the plugin raises from its
      // own catch-all is the case this exists for: a mapping that threw on an
      // unrecognised code would turn a routine failure into a second crash.
      final PanelNote note = panelShowFailureNote(
        PlatformException(code: 'android_panel_restore_failed'),
        copy,
      );

      expect(note.text, copy.text(CopyKey.runtimePanelShowFailed));
      expect(note.remedy, isNull);
    });
  });

  group('the codes the platform actually raises', () {
    final File plugin = File(
      '${Directory.current.absolute.path}/../..'
      '/packages/miaotou_capabilities_android/android/src/main/kotlin'
      '/com/miaotoujunshi/capabilities/android/MiaotouAndroidPlugin.kt',
    );

    test('the Kotlin side is still where this test thinks it is', () {
      expect(
        plugin.existsSync(),
        isTrue,
        reason: 'this guard is worthless if it silently reads nothing: '
            '${plugin.path}',
      );
    });

    test('every overlay code the plugin raises has an answer in Dart', () {
      // String literals rather than a parse: the codes are written as literals
      // in `result.error(...)` and there is no generated artifact between the two
      // sides. A new code added in Kotlin fails this test, which is the point —
      // the alternative is what ADR-0021 was written to undo, four codes raised
      // into a `catch` block that did not exist.
      final Set<String> raised = RegExp(r'"overlay_permission_[a-z_]+"')
          .allMatches(plugin.readAsStringSync())
          .map((RegExpMatch match) => match.group(0)!.replaceAll('"', ''))
          .toSet();

      expect(
        raised,
        <String>{
          'overlay_permission_unavailable',
          'overlay_permission_pending',
          'overlay_permission_denied',
        },
        reason: 'the Kotlin side changed the codes `show()` raises; the mapping '
            'in `capability_registry.dart` and the copy that goes with it have '
            'to change in the same commit',
      );

      for (final String code in raised) {
        // Every one of them lands on a sentence rather than on a rethrow.
        expect(
          panelShowFailureNote(PlatformException(code: code), copy).text,
          isNotEmpty,
          reason: '$code would leave the user with an exception and no panel',
        );
      }
    });

    test('the accessibility code stays the one with its own sentence', () {
      // The other half of the same boundary, and the one that predates this
      // ticket: `withCaptureService` raises it before any capture machinery runs.
      // It is answered in `conversation_runtime.dart` rather than here, because
      // it arrives on the capture path and not on the show path.
      final String kotlin = plugin.readAsStringSync();

      expect(kotlin, contains('"accessibility_service_unavailable"'));
      expect(
        copy.text(CopyKey.runtimeCaptureServiceOff),
        contains('无障碍'),
        reason: 'the sentence has to name the service the system settings call '
            '无障碍, or the user cannot find the row to switch on',
      );
    });
  });
}
