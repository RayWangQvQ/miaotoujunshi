import 'dart:async';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'native.dart';
import 'pacing.dart';
import 'placement.dart';

/// macOS's answer for screen capture.
///
/// Owned by #14. The mechanism this port keeps is ScreenCaptureKit: Quartz's
/// `CGWindowListCreateImage` was obsoleted in macOS 15, so that rewrite is
/// required whether or not the port migrates at all (ADR-0007 decision 7). It is
/// also the only mechanism that answers the question the product is built on —
/// **a window can be captured while something else is in front of it**, which is
/// the whole reason the panel may float above the chat.
final class MacosScreenCapture implements ScreenCapture {
  MacosScreenCapture(this._native, this._panel, {CapturePacing? pacing})
      : pacing = pacing ?? CapturePacing();

  final MacosNative _native;

  /// The panel this capture has to get out of its own way for.
  final MacosFloatingPanel _panel;

  /// The rate limit, the backoff and the watchdog. Exposed because they are the
  /// three numbers a support question is actually about.
  final CapturePacing pacing;

  @override
  Future<String?> findTargetWindow() => _native.findTargetWindow();

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) => pacing.run(() async {
        // The panel is hidden for the duration of the shot, not merely for the
        // pixels: a window captured with the panel on top of it returns the panel,
        // and the conversation underneath is then analysed as if the user had said
        // it. The restore is in a `finally` because a capture that fails, hangs or
        // trips the watchdog must still give the panel back.
        await _panel.hideForCapture();
        try {
          return await _native.capture(targetWindowId: targetWindowId);
        } finally {
          await _panel.restoreAfterCapture();
        }
      });
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
///
/// **Recognition only.** Deciding who said a line is geometry, and geometry is
/// calibrated per window, so it lives in `perception.dart` beside the numbers it
/// was measured against rather than here beside the engine. The two are ported
/// together and tested together; splitting them would leave the thresholds with
/// no way to be exercised.
final class MacosOcr implements Ocr {
  const MacosOcr(this._native);

  final MacosNative _native;

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) =>
      _native.recognize(frame, languages: languages);
}

/// macOS's answer for injecting text.
///
/// Owned by #14. Writes into the target's accessibility text control and reads
/// `AXValue` back before reporting success, because the contract's whole point is
/// that "I wrote it" is not an answer (ADR-0009 decision 5).
///
/// **There is no send path, and there is no member that could become one.** No
/// keystroke is synthesised, no `AXPress` is performed, and the return key is
/// never posted — the guard test in the application scans the Swift for all three
/// so that adding one is a red test rather than a code review's memory.
final class MacosTextInject implements TextInject {
  const MacosTextInject(this._native);

  final MacosNative _native;

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) =>
      _native.inject(text, target: target);
}

/// macOS's answer for the floating window.
///
/// Owned by #14. The window is an `NSPanel` with `.nonactivatingPanel` at
/// `.floating`, which is what gate experiment B established on a real device
/// (ADR-0007 milestone M0): the panel can be clicked and can host a Chinese input
/// method while the chat stays the frontmost application.
///
/// What lives here and what lives natively is a split with a reason. **The window
/// is native** — AppKit owns its level, its style mask and whether it may become
/// key, and none of those are things Dart can express. **The arithmetic is Dart** —
/// which edge a drag landed nearest to, and where the panel was last put, are
/// decisions that can be wrong in ways a device is the only way to observe, so
/// they are made where a test can reach them.
final class MacosFloatingPanel implements FloatingPanel {
  MacosFloatingPanel(
    this._native, {
    PanelPositionMemory? memory,
    this.hideSettle = const Duration(milliseconds: 120),
  }) : _memory = memory ?? PanelPositionMemory();

  final MacosNative _native;
  final PanelPositionMemory _memory;

  /// How long the compositor is given to actually drop the panel's frame.
  ///
  /// Ordering a window out is a request, not an event: a capture fired in the same
  /// tick photographs a panel that is on its way off the screen, and the
  /// conversation underneath is then read with the panel's own header in it. The
  /// value is the Android port's measured 120 ms **carried over, not measured
  /// here** — this machine has no window server to measure on, and guessing a
  /// smaller number would be a claim nobody checked. It is a constructor argument
  /// so #16 can replace it with a measurement instead of an inheritance.
  final Duration hideSettle;

  /// Whether the panel was on screen when the capture asked it to leave, and so
  /// whether it has to be given back. Restoring a panel the user had closed would
  /// be a window that reappears by itself.
  bool _upBeforeCapture = false;

  @override
  Future<void> show({required PanelPlacement placement}) async {
    ScreenRect? at;
    if (placement.anchor == PanelAnchor.free) {
      final PanelGeometry geometry = await _native.panelGeometry();
      at = _memory.resolve(
        placement: placement,
        screen: geometry.screen,
        size: geometry.window,
      );
    }
    await _native.showPanel(placement: placement, at: at);
  }

  @override
  Future<void> hide() async {
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
  late final Stream<PanelEvent> events = _reduce();

  Stream<PanelEvent> _reduce() {
    final StreamController<PanelEvent> out = StreamController<PanelEvent>();
    _native.events.listen(
      (NativePanelEvent event) async {
        switch (event) {
          case NativePanelDragged(:final ScreenRect window, :final ScreenRect screen):
            final ScreenRect landed = EdgeSnap.snap(window, screen);
            _memory.remember(landed);
            // The snap is applied by asking for the window again rather than by
            // telling Dart where it went: the window is the only thing that knows
            // where it actually is, and a report of where it *should* be is not
            // what the contract publishes.
            await _native.showPanel(
              placement: const PanelPlacement(anchor: PanelAnchor.free),
              at: landed,
            );
            out.add(PanelDragged(x: landed.left, y: landed.top));
          case NativePanelTapped(:final String action):
            out.add(PanelTapped(action: action));
          case NativePanelReadOnly(:final bool readOnly):
            out.add(PanelReadOnlyChanged(readOnly: readOnly));
        }
      },
      onError: out.addError,
    );
    return out.stream;
  }
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
