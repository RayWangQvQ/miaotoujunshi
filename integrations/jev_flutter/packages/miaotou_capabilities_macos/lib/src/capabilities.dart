import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// macOS's answer for screen capture.
///
/// Owned by #14. The mechanism this port keeps is ScreenCaptureKit: Quartz's
/// `CGWindowListCreateImage` was obsoleted in macOS 15, so that rewrite is
/// required whether or not the port migrates at all (ADR-0007 decision 7).
final class MacosScreenCapture implements ScreenCapture {
  const MacosScreenCapture();

  static const String _platform = 'macOS';

  @override
  Future<String?> findTargetWindow() async => notYetBuilt(
        platform: _platform,
        member: 'ScreenCapture.findTargetWindow',
        ticket: '#14',
      );

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async => notYetBuilt(
        platform: _platform,
        member: 'ScreenCapture.capture',
        ticket: '#14',
      );
}

/// macOS's answer for reading another application's view of itself.
///
/// **Permanent refusal.** No desktop port reads an accessibility node tree to
/// find the conversation: everything they know arrives as pixels, and the text
/// is recovered by OCR. This is the case ADR-0009 decision 2 was written for, and
/// the reason the refusal is `UnsupportedError` rather than a not-yet.
final class MacosUiTreeReader implements UiTreeReader {
  const MacosUiTreeReader();

  static const String _platform = 'macOS';
  static const String _reason =
      'the desktop ports read pixels, not accessibility nodes; the words come '
      'back through Ocr';

  @override
  Future<ChatUiSnapshot?> readActiveChat() async => unsupportedOnThisPlatform(
        platform: _platform,
        member: 'UiTreeReader.readActiveChat',
        reason: _reason,
      );

  @override
  Stream<ChatUiSnapshot> get snapshots => unsupportedOnThisPlatform(
        platform: _platform,
        member: 'UiTreeReader.snapshots',
        reason: _reason,
      );
}

/// macOS's answer for OCR.
///
/// Owned by #14. Backed by Apple Vision.
final class MacosOcr implements Ocr {
  const MacosOcr();

  static const String _platform = 'macOS';

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async =>
      notYetBuilt(
        platform: _platform,
        member: 'Ocr.recognize',
        ticket: '#14',
      );
}

/// macOS's answer for injecting text.
///
/// Owned by #14. Verifies the landing by reading `AXValue` back.
final class MacosTextInject implements TextInject {
  const MacosTextInject();

  static const String _platform = 'macOS';

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async =>
      notYetBuilt(
        platform: _platform,
        member: 'TextInject.inject',
        ticket: '#14',
      );
}

/// macOS's answer for the floating window.
///
/// Owned by #14. The panel is an `NSPanel` with `.nonactivatingPanel`, which is
/// what the gate-B experiment on a real device established (ADR-0007 milestone
/// M0).
final class MacosFloatingPanel implements FloatingPanel {
  const MacosFloatingPanel();

  static const String _platform = 'macOS';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#14',
      );

  @override
  Future<void> show({required PanelPlacement placement}) async =>
      _refuse('FloatingPanel.show');

  @override
  Future<void> hide() async => _refuse('FloatingPanel.hide');

  @override
  Future<void> hideForCapture() async => _refuse('FloatingPanel.hideForCapture');

  @override
  Future<void> restoreAfterCapture() async =>
      _refuse('FloatingPanel.restoreAfterCapture');

  @override
  Future<void> setFocusable(bool value) async =>
      _refuse('FloatingPanel.setFocusable');

  @override
  Stream<PanelEvent> get events => _refuse('FloatingPanel.events');
}

/// macOS's answer for the shared payload.
///
/// Owned by #15. Reads real files under `.app/Contents/Resources/`, which keeps
/// "read files at runtime" literally true (ADR-0008 decision 2).
final class MacosSharedPayload implements SharedPayload {
  const MacosSharedPayload();

  static const String _platform = 'macOS';

  @override
  Future<Uint8List> read(String repoRelativePath) async => notYetBuilt(
        platform: _platform,
        member: 'SharedPayload.read',
        ticket: '#15',
      );

  @override
  Future<List<String>> list(String repoRelativeDir) async => notYetBuilt(
        platform: _platform,
        member: 'SharedPayload.list',
        ticket: '#15',
      );
}

/// macOS's answer for small remembered values.
///
/// Owned by #15. Backed by a property list under the application container;
/// credentials do not go here.
final class MacosPreferences implements Preferences {
  const MacosPreferences();

  static const String _platform = 'macOS';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#15',
      );

  @override
  Future<String?> getString(String key) async => _refuse('Preferences.getString');

  @override
  Future<bool?> getBool(String key) async => _refuse('Preferences.getBool');

  @override
  Future<int?> getInt(String key) async => _refuse('Preferences.getInt');

  @override
  Future<List<String>?> getStringList(String key) async =>
      _refuse('Preferences.getStringList');

  @override
  Future<void> setString(String key, String value) async =>
      _refuse('Preferences.setString');

  @override
  Future<void> setBool(String key, bool value) async =>
      _refuse('Preferences.setBool');

  @override
  Future<void> setInt(String key, int value) async =>
      _refuse('Preferences.setInt');

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _refuse('Preferences.setStringList');

  @override
  Future<void> remove(String key) async => _refuse('Preferences.remove');

  @override
  Future<Set<String>> keys() async => _refuse('Preferences.keys');
}

/// macOS's answer for credentials.
///
/// Owned by #15. The Keychain, which is the store this port already uses.
final class MacosSecretStore implements SecretStore {
  const MacosSecretStore();

  static const String _platform = 'macOS';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#15',
      );

  @override
  Future<String?> read(String key) async => _refuse('SecretStore.read');

  @override
  Future<void> write(String key, String value) async =>
      _refuse('SecretStore.write');

  @override
  Future<void> delete(String key) async => _refuse('SecretStore.delete');

  @override
  Future<Set<String>> keys() async => _refuse('SecretStore.keys');
}

/// macOS's answer for the knowledge base.
///
/// Owned by #15. The union baseline (ADR-0007 decision 4) means this port keeps a
/// capability it never had: the knowledge base used to be Android's alone.
final class MacosKnowledgeStore implements KnowledgeStore {
  const MacosKnowledgeStore();

  static const String _platform = 'macOS';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#15',
      );

  @override
  Future<List<KnowledgeNote>> notes() async => _refuse('KnowledgeStore.notes');

  @override
  Future<void> saveNote(KnowledgeNote note) async =>
      _refuse('KnowledgeStore.saveNote');

  @override
  Future<void> deleteNote(String id) async =>
      _refuse('KnowledgeStore.deleteNote');

  @override
  Future<List<KnowledgeContact>> contacts() async =>
      _refuse('KnowledgeStore.contacts');

  @override
  Future<KnowledgeContact?> findContact({
    required String title,
    required String packageName,
  }) async =>
      _refuse('KnowledgeStore.findContact');

  @override
  Future<void> saveContact(KnowledgeContact contact) async =>
      _refuse('KnowledgeStore.saveContact');

  @override
  Future<void> deleteContact(String id) async =>
      _refuse('KnowledgeStore.deleteContact');

  @override
  Future<void> appendLog(String contactId, List<KnowledgeLogEntry> entries) async =>
      _refuse('KnowledgeStore.appendLog');

  @override
  Future<List<KnowledgeLogEntry>> recentLog(
    String contactId, {
    required int limit,
  }) async =>
      _refuse('KnowledgeStore.recentLog');

  @override
  Future<void> clearAll() async => _refuse('KnowledgeStore.clearAll');
}

/// macOS's answer for the memory store.
///
/// Owned by #15. Implemented in Dart on all three ports rather than shelled out
/// to a Python script, which is what removes this port's subprocess coupling
/// (ADR-0010).
final class MacosMemoryStore implements MemoryStore {
  const MacosMemoryStore();

  static const String _platform = 'macOS';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#15',
      );

  @override
  Future<MemoryStatus> status() async => _refuse('MemoryStore.status');

  @override
  Future<List<MemoryRecord>> show(String subjectId) async =>
      _refuse('MemoryStore.show');

  @override
  Future<void> apply({
    required String subjectId,
    required String field,
    required String value,
  }) async =>
      _refuse('MemoryStore.apply');

  @override
  Future<int> undo() async => _refuse('MemoryStore.undo');
}
