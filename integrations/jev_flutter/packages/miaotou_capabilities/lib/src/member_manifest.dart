import 'dart:typed_data';

import 'capability_set.dart';
import 'model/speaker.dart';
import 'platform/floating_panel.dart';
import 'platform/screen_capture.dart';
import 'platform/text_inject.dart';
import 'storage/knowledge_store.dart';

/// Every member of the ten interfaces, named, as a call that must go somewhere.
///
/// One entry per member — forty-two of them — so that a port's test can drive the
/// whole contract and assert, member by member, that it answered or refused. A
/// member that returned null, an empty list or a default comes back as
/// `SupportAnswer.answered` from `askCapability`, which is exactly why the
/// assertions are written per platform rather than here.
///
/// This is a manifest of the contract's surface, not test scaffolding: it is what
/// makes "every member is answered for" checkable at all, and a support report
/// asks the same table. That is why it lives in the shipping library while the
/// in-memory implementation lives behind `testing.dart`.
///
/// **Adding a member to an interface means adding it here.** The compiler will
/// not say so — a manifest is a list, not a type — so the count is asserted in
/// `contract_test.dart`.
final Map<String, Future<Object?> Function(CapabilitySet)> capabilityProbes =
    <String, Future<Object?> Function(CapabilitySet)>{
  'screenCapture.findTargetWindow': (CapabilitySet c) =>
      c.screenCapture.findTargetWindow(),
  'screenCapture.capture': (CapabilitySet c) => c.screenCapture.capture(),

  'uiTreeReader.readActiveChat': (CapabilitySet c) =>
      c.uiTreeReader.readActiveChat(),
  'uiTreeReader.snapshots': (CapabilitySet c) async => c.uiTreeReader.snapshots,

  'ocr.recognize': (CapabilitySet c) =>
      c.ocr.recognize(probeFrame(), languages: const <String>['zh-Hans']),

  'textInject.inject': (CapabilitySet c) => c.textInject.inject(
        '你好',
        target: const InjectTarget(windowId: 'probe'),
      ),

  'floatingPanel.show': (CapabilitySet c) => c.floatingPanel.show(
        placement: const PanelPlacement(anchor: PanelAnchor.topRight),
      ),
  'floatingPanel.hide': (CapabilitySet c) => c.floatingPanel.hide(),
  'floatingPanel.hideForCapture': (CapabilitySet c) =>
      c.floatingPanel.hideForCapture(),
  'floatingPanel.restoreAfterCapture': (CapabilitySet c) =>
      c.floatingPanel.restoreAfterCapture(),
  'floatingPanel.setFocusable': (CapabilitySet c) =>
      c.floatingPanel.setFocusable(true),
  'floatingPanel.events': (CapabilitySet c) async => c.floatingPanel.events,

  'sharedPayload.read': (CapabilitySet c) =>
      c.sharedPayload.read('miaotoujunshi/references/data/trend-rules.json'),
  'sharedPayload.list': (CapabilitySet c) =>
      c.sharedPayload.list('miaotoujunshi/references/data'),

  'preferences.getString': (CapabilitySet c) => c.preferences.getString('probe'),
  'preferences.getBool': (CapabilitySet c) => c.preferences.getBool('probe'),
  'preferences.getInt': (CapabilitySet c) => c.preferences.getInt('probe'),
  'preferences.getStringList': (CapabilitySet c) =>
      c.preferences.getStringList('probe'),
  'preferences.setString': (CapabilitySet c) =>
      c.preferences.setString('probe', 'x'),
  'preferences.setBool': (CapabilitySet c) =>
      c.preferences.setBool('probe', true),
  'preferences.setInt': (CapabilitySet c) => c.preferences.setInt('probe', 1),
  'preferences.setStringList': (CapabilitySet c) =>
      c.preferences.setStringList('probe', const <String>['x']),
  'preferences.remove': (CapabilitySet c) => c.preferences.remove('probe'),
  'preferences.keys': (CapabilitySet c) => c.preferences.keys(),

  'secretStore.read': (CapabilitySet c) => c.secretStore.read('probe'),
  'secretStore.write': (CapabilitySet c) => c.secretStore.write('probe', 'x'),
  'secretStore.delete': (CapabilitySet c) => c.secretStore.delete('probe'),
  'secretStore.keys': (CapabilitySet c) => c.secretStore.keys(),

  'knowledgeStore.notes': (CapabilitySet c) => c.knowledgeStore.notes(),
  'knowledgeStore.saveNote': (CapabilitySet c) => c.knowledgeStore.saveNote(
        KnowledgeNote(
          id: 'probe',
          title: 'probe',
          content: 'probe',
          updatedAt: DateTime(2026),
        ),
      ),
  'knowledgeStore.deleteNote': (CapabilitySet c) =>
      c.knowledgeStore.deleteNote('probe'),
  'knowledgeStore.contacts': (CapabilitySet c) => c.knowledgeStore.contacts(),
  'knowledgeStore.findContact': (CapabilitySet c) =>
      c.knowledgeStore.findContact(title: 'probe', packageName: 'probe'),
  'knowledgeStore.saveContact': (CapabilitySet c) =>
      c.knowledgeStore.saveContact(
        KnowledgeContact(id: 'probe', name: 'probe', updatedAt: DateTime(2026)),
      ),
  'knowledgeStore.deleteContact': (CapabilitySet c) =>
      c.knowledgeStore.deleteContact('probe'),
  'knowledgeStore.appendLog': (CapabilitySet c) =>
      c.knowledgeStore.appendLog('probe', <KnowledgeLogEntry>[
        KnowledgeLogEntry(
          speaker: Speaker.me,
          text: 'probe',
          timestamp: DateTime(2026),
          packageName: 'probe',
        ),
      ]),
  'knowledgeStore.recentLog': (CapabilitySet c) =>
      c.knowledgeStore.recentLog('probe', limit: 1),
  'knowledgeStore.clearAll': (CapabilitySet c) => c.knowledgeStore.clearAll(),

  'memoryStore.status': (CapabilitySet c) => c.memoryStore.status(),
  'memoryStore.show': (CapabilitySet c) => c.memoryStore.show('probe'),
  'memoryStore.apply': (CapabilitySet c) => c.memoryStore.apply(
        subjectId: 'probe',
        field: 'stage',
        value: 'probe',
      ),
  'memoryStore.undo': (CapabilitySet c) => c.memoryStore.undo(),
};

/// A small opaque frame for the probes that need one.
///
/// Built here rather than borrowed from a capture, so that asking about OCR does
/// not depend on asking about screen capture first.
CaptureFrame probeFrame() => CaptureFrame(
      pixels: Uint8List.fromList(List<int>.filled(2 * 2 * 4, 0xff)),
      width: 2,
      height: 2,
      scaleX: 1,
      scaleY: 1,
      originX: 0,
      originY: 0,
    );
