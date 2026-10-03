import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Windows's answer for screen capture.
///
/// Owned by #17. Capture runs inside the out-of-process native bridge around
/// Windows Graphics Capture (ADR-0013). It is the largest hand-written surface
/// in the migration and the port most likely to overrun.
final class WindowsScreenCapture implements ScreenCapture {
  const WindowsScreenCapture();

  static const String _platform = 'Windows';

  @override
  Future<String?> findTargetWindow() async => notYetBuilt(
        platform: _platform,
        member: 'ScreenCapture.findTargetWindow',
        ticket: '#17',
      );

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async => notYetBuilt(
        platform: _platform,
        member: 'ScreenCapture.capture',
        ticket: '#17',
      );
}

/// Windows's answer for reading another application's view of itself.
///
/// **Permanent refusal.** No desktop port reads an accessibility node tree to
/// find the conversation: everything they know arrives as pixels, and the text
/// is recovered by OCR. This is the case ADR-0009 decision 2 was written for, and
/// the reason the refusal is `UnsupportedError` rather than a not-yet.
final class WindowsUiTreeReader implements UiTreeReader {
  const WindowsUiTreeReader();

  static const String _platform = 'Windows';
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

/// Windows's answer for OCR.
///
/// Owned by #17. The recognition runs inside the same native bridge as capture —
/// Rust over ONNX Runtime, reusing RapidOCR's models and its post-processing —
/// rather than in Dart (ADR-0009 decision 6). DBNet's post-processing needs
/// contour detection and a perspective crop with no Dart equivalent.
final class WindowsOcr implements Ocr {
  const WindowsOcr();

  static const String _platform = 'Windows';

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async =>
      notYetBuilt(
        platform: _platform,
        member: 'Ocr.recognize',
        ticket: '#17',
      );
}

/// Windows's answer for injecting text.
///
/// Owned by #17. Verifies the landing by reading the field's text back through
/// the same native helper that injected it.
final class WindowsTextInject implements TextInject {
  const WindowsTextInject();

  static const String _platform = 'Windows';

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async =>
      notYetBuilt(
        platform: _platform,
        member: 'TextInject.inject',
        ticket: '#17',
      );
}

/// Windows's answer for the floating window.
///
/// Owned by #18. A frameless, always-on-top window that owns only the ball and
/// the panel; every other surface is a route in the main window (ADR-0012).
final class WindowsFloatingPanel implements FloatingPanel {
  const WindowsFloatingPanel();

  static const String _platform = 'Windows';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#18',
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

/// Windows's answer for the shared payload.
///
/// Owned by #19. Reads the real files that sit next to the executable, which
/// keeps "read files at runtime" literally true (ADR-0008 decision 2).
final class WindowsSharedPayload implements SharedPayload {
  const WindowsSharedPayload();

  static const String _platform = 'Windows';

  @override
  Future<Uint8List> read(String repoRelativePath) async => notYetBuilt(
        platform: _platform,
        member: 'SharedPayload.read',
        ticket: '#19',
      );

  @override
  Future<List<String>> list(String repoRelativeDir) async => notYetBuilt(
        platform: _platform,
        member: 'SharedPayload.list',
        ticket: '#19',
      );
}

/// Windows's answer for small remembered values.
///
/// Owned by #19. Backed by a file under the user's application data directory;
/// credentials do not go here.
final class WindowsPreferences implements Preferences {
  const WindowsPreferences();

  static const String _platform = 'Windows';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#19',
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

/// Windows's answer for credentials.
///
/// Owned by #19. The Windows Credential Manager.
final class WindowsSecretStore implements SecretStore {
  const WindowsSecretStore();

  static const String _platform = 'Windows';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#19',
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

/// Windows's answer for the knowledge base.
///
/// Owned by #15. The union baseline (ADR-0007 decision 4) means this port keeps a
/// capability it never had: the knowledge base used to be Android's alone.
final class WindowsKnowledgeStore implements KnowledgeStore {
  const WindowsKnowledgeStore();

  static const String _platform = 'Windows';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#19',
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

/// Windows's answer for the memory store.
///
/// Owned by #19. Implemented in Dart, which is the only option here: this port
/// has no Python interpreter to shell out to at all (ADR-0010).
final class WindowsMemoryStore implements MemoryStore {
  const WindowsMemoryStore();

  static const String _platform = 'Windows';

  Never _refuse(String member) => notYetBuilt(
        platform: _platform,
        member: member,
        ticket: '#19',
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
