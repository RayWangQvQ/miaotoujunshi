import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel_native.dart';

/// Android's answer for screen capture.
///
/// Owned by #22. The `takeScreenshot` / `takeScreenshotOfWindow` calls stay in
/// Kotlin, along with the 1s rate limit, the 1→30s backoff and the 3s watchdog
/// that were calibrated on real devices (ADR-0009 decision 1).
///
/// A frame here is a *window*, not the screen, which is why CaptureFrame carries
/// the origin and the scale that map it back.
final class AndroidScreenCapture implements ScreenCapture {
  const AndroidScreenCapture();

  static const String _platform = 'Android';

  @override
  Future<String?> findTargetWindow() async => notYetBuilt(
    platform: _platform,
    member: 'ScreenCapture.findTargetWindow',
    ticket: '#22',
  );

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async => notYetBuilt(
    platform: _platform,
    member: 'ScreenCapture.capture',
    ticket: '#22',
  );
}

/// Android's answer for reading the foreground application's own view of itself.
///
/// Owned by #22. **This is the capability only Android has.** An
/// `AccessibilityService` wakes on a content change and hands over a node tree,
/// which is how this port reads a conversation without photographing it — and
/// why the two desktop packages refuse the same interface permanently
/// (ADR-0009 decision 2). The service itself stays Kotlin: it is a system-bound
/// component that Flutter neither can nor needs to host (ADR-0007 decision 5).
final class AndroidUiTreeReader implements UiTreeReader {
  const AndroidUiTreeReader();

  static const String _platform = 'Android';

  @override
  Future<ChatUiSnapshot?> readActiveChat() async => notYetBuilt(
    platform: _platform,
    member: 'UiTreeReader.readActiveChat',
    ticket: '#22',
  );

  @override
  Stream<ChatUiSnapshot> get snapshots => notYetBuilt(
    platform: _platform,
    member: 'UiTreeReader.snapshots',
    ticket: '#22',
  );
}

/// Android's answer for OCR.
///
/// Owned by #22. Backed by ML Kit, and also by the cloud vision route the port
/// already offers — the one endpoint that sends a screenshot anywhere, and the
/// reason the visibility question in PRIVACY.md stays open.
final class AndroidOcr implements Ocr {
  const AndroidOcr();

  static const String _platform = 'Android';

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async =>
      notYetBuilt(platform: _platform, member: 'Ocr.recognize', ticket: '#22');
}

/// Android's answer for injecting text.
///
/// Owned by #22. `ACTION_SET_TEXT` or `ACTION_PASTE`, and the landing is verified
/// by reading the node's text back.
final class AndroidTextInject implements TextInject {
  const AndroidTextInject();

  static const String _platform = 'Android';

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async => notYetBuilt(
    platform: _platform,
    member: 'TextInject.inject',
    ticket: '#22',
  );
}

/// Android's answer for the floating window.
///
/// Owned by #21. A hand-written Kotlin plugin, not `flutter_overlay_window`: that
/// package has had no commit in fifteen months and its open defects include a
/// hang in `closeOverlay()` (ADR-0007). The plugin owns the window semantics; the
/// panel's content is rendered by Flutter in a second engine, and the gate-A
/// experiment on a real device is what established that all four rendering pieces
/// are required.
final class AndroidFloatingPanel implements FloatingPanel {
  AndroidFloatingPanel({
    AndroidPanelNative? native,
    this.hideSettle = const Duration(milliseconds: 120),
  }) : _native = native ?? MethodChannelAndroidPanelNative();

  final AndroidPanelNative _native;
  final Duration hideSettle;
  bool _upBeforeCapture = false;

  @override
  Future<void> show({required PanelPlacement placement}) =>
      _native.showPanel(placement);

  @override
  Future<void> hide() async {
    _upBeforeCapture = false;
    await _native.hidePanel();
  }

  @override
  Future<void> hideForCapture() async {
    _upBeforeCapture = await _native.hidePanel();
    if (_upBeforeCapture) {
      await Future<void>.delayed(hideSettle);
    }
  }

  @override
  Future<void> restoreAfterCapture() async {
    if (!_upBeforeCapture) {
      return;
    }
    _upBeforeCapture = false;
    await _native.restorePanel();
  }

  @override
  Future<void> setFocusable(bool value) => _native.setPanelFocusable(value);

  @override
  late final Stream<PanelEvent> events = _native.panelEvents.map(
    (AndroidPanelEvent event) => switch (event) {
      AndroidPanelDragged(:final double x, :final double y) => PanelDragged(
        x: x,
        y: y,
      ),
      AndroidPanelTapped(:final String action) => PanelTapped(action: action),
      AndroidPanelReadOnly(:final bool readOnly) => PanelReadOnlyChanged(
        readOnly: readOnly,
      ),
    },
  );
}

/// Android's answer for the shared payload.
///
/// Owned by #23. This is the one legacy mechanism reused verbatim: the existing
/// Gradle copy task (`Sync`, not `Copy`) plus recursive assets packaging, read
/// back through the `AssetManager` over a channel (ADR-0008 decision 2).
final class AndroidSharedPayload implements SharedPayload {
  const AndroidSharedPayload();

  static const String _platform = 'Android';

  @override
  Future<Uint8List> read(String repoRelativePath) async => notYetBuilt(
    platform: _platform,
    member: 'SharedPayload.read',
    ticket: '#23',
  );

  @override
  Future<List<String>> list(String repoRelativeDir) async => notYetBuilt(
    platform: _platform,
    member: 'SharedPayload.list',
    ticket: '#23',
  );
}

/// Android's answer for small remembered values.
///
/// Owned by #23. Backed by `SharedPreferences` in the application's private
/// storage; credentials do not go here.
final class AndroidPreferences implements Preferences {
  const AndroidPreferences();

  static const String _platform = 'Android';

  Never _refuse(String member) =>
      notYetBuilt(platform: _platform, member: member, ticket: '#23');

  @override
  Future<String?> getString(String key) async =>
      _refuse('Preferences.getString');

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

/// Android's answer for credentials.
///
/// Owned by #23. Application-private storage, backed by the Keystore where the
/// device provides one; never world-readable, never logged, never committed.
final class AndroidSecretStore implements SecretStore {
  const AndroidSecretStore();

  static const String _platform = 'Android';

  Never _refuse(String member) =>
      notYetBuilt(platform: _platform, member: member, ticket: '#23');

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

/// Android's answer for the knowledge base.
///
/// Owned by #15. The union baseline (ADR-0007 decision 4) means this port keeps a
/// capability it never had: the knowledge base used to be Android's alone.
final class AndroidKnowledgeStore implements KnowledgeStore {
  const AndroidKnowledgeStore();

  static const String _platform = 'Android';

  Never _refuse(String member) =>
      notYetBuilt(platform: _platform, member: member, ticket: '#23');

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
  }) async => _refuse('KnowledgeStore.findContact');

  @override
  Future<void> saveContact(KnowledgeContact contact) async =>
      _refuse('KnowledgeStore.saveContact');

  @override
  Future<void> deleteContact(String id) async =>
      _refuse('KnowledgeStore.deleteContact');

  @override
  Future<void> appendLog(
    String contactId,
    List<KnowledgeLogEntry> entries,
  ) async => _refuse('KnowledgeStore.appendLog');

  @override
  Future<List<KnowledgeLogEntry>> recentLog(
    String contactId, {
    required int limit,
  }) async => _refuse('KnowledgeStore.recentLog');

  @override
  Future<void> clearAll() async => _refuse('KnowledgeStore.clearAll');
}

/// Android's answer for the memory store.
///
/// Owned by #23. Implemented in Dart, which is the only option: this port has no
/// Python interpreter to shell out to at all (ADR-0010).
final class AndroidMemoryStore implements MemoryStore {
  const AndroidMemoryStore();

  static const String _platform = 'Android';

  Never _refuse(String member) =>
      notYetBuilt(platform: _platform, member: member, ticket: '#23');

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
  }) async => _refuse('MemoryStore.apply');

  @override
  Future<int> undo() async => _refuse('MemoryStore.undo');
}
