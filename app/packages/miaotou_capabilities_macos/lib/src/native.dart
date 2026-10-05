import 'dart:async';

import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// Everything this port needs macOS to do for it, as one seam.
///
/// The boundary is a single method channel rather than a plugin class per
/// capability, for one reason: the panel is a **second Flutter engine in a second
/// `NSPanel`**, and that engine is created by the same native code that has to
/// place the window and read the drag back. Splitting it across four plugin
/// classes would mean four objects holding one window between them.
///
/// #15 added six members to this interface and the rule that decided them is the
/// one #14 established: **an error a test can catch belongs above this file, and
/// only something that is knowable solely on the device belongs on it.** So:
///
/// * **The payload's location is here; the payload's reading is not.** A packaged
///   `.app` has no idea what a repository-relative path means, and only
///   `Bundle.main.resourcePath` knows where the tree landed. Everything after
///   that — joining, reading bytes, refusing a missing file — is `dart:io` and is
///   exercised on a fake in milliseconds.
/// * **The container directory is here; the file formats are not.** Only the
///   sandbox knows which directory this app may write, and the three stores that
///   live there differ in what they write, not in where.
/// * **The Keychain is here, entirely.** `SecItem*` is C API in
///   `Security.framework`; there is no Dart expression of it, and a sandboxed
///   app cannot reach `/usr/bin/security` as a subprocess the way the frozen
///   Python port did. This is the only storage work with no pure-Dart half.
///
/// Everything above this file is pure Dart and testable without a device; this is
/// the line where the tests stop.
abstract interface class MacosNative {
  /// The chat window to capture, or null when there is none in front.
  Future<String?> findTargetWindow();

  /// One frame of [targetWindowId], or of the screen when it is null.
  Future<CaptureOutcome> capture({String? targetWindowId});

  Future<List<OcrLine>> recognize(CaptureFrame frame, {required List<String> languages});

  Future<InjectResult> inject(String text, {required InjectTarget target});

  /// Where the panel is, and how big the screen it is on is.
  ///
  /// Needed before the panel can be placed from Dart: snapping a window to an
  /// edge is arithmetic over a rectangle, and this is the only way to get one.
  Future<PanelGeometry> panelGeometry();

  /// Shows or re-places the panel. [at] wins over [placement] when it is given.
  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at});

  /// Takes the panel off screen and reports whether it was on screen, so a
  /// capture can give back exactly what it took.
  Future<bool> hidePanel();

  /// Puts the panel back **where it was**.
  ///
  /// Not the same as asking to show it again: a show resolves an anchor or an
  /// offset, and a panel that was never dragged has neither, so restoring through
  /// it would move the window to the corner the moment the first capture ended.
  Future<void> restorePanel();

  /// Lets the panel take keyboard focus — and no more than that. This is the
  /// switch between "a field the user can type into" and "a ball that must never
  /// take the caret out of the chat".
  Future<void> setPanelFocusable(bool value);

  /// What the panel reports, richer than [PanelEvent] on purpose: the drag needs
  /// the window's size to be snapped, and the contract's [PanelDragged] has no
  /// room for one.
  Stream<NativePanelEvent> get events;

  // ---------------------------------------------------------------------------
  // #15. The three answers below are all *locations or the Keychain*, and the
  // file header says why each of them could not be answered in Dart.
  // ---------------------------------------------------------------------------

  /// Where the payload tree was synced: `.app/Contents/Resources`.
  ///
  /// **This has to be native.** A packaged application has no repository above
  /// it and no compile-time idea where its own bundle is; the path only exists
  /// once AppKit has laid the bundle out. It is also the *only* thing the
  /// payload needs from the platform — the read itself is `dart:io`, and
  /// `MacosSharedPayload` does that part with a fake root in a unit test.
  ///
  /// The build phase is what puts something there at all; see
  /// `apps/miaotou_app/macos/Runner.xcodeproj` and ADR-0008.
  Future<String> resourceRoot();

  /// A directory this app may write, and the only one it should.
  ///
  /// **This has to be native.** Under the sandbox the home directory is not
  /// writable, and `NSApplicationSupportDirectory` is the location the system
  /// hands a sandboxed app for exactly this. A Dart implementation would have to
  /// hard-code a path, and a hard-coded path is either wrong on somebody's
  /// machine or a second place to change when it moves.
  ///
  /// The three stores below share this one directory and each owns a file in
  /// it. They do not share a format.
  Future<String> containerDirectory();

  /// The value stored under [key] in the system Keychain, or null.
  ///
  /// **This has to be native.** `SecItemCopyMatching` is the only way in, and
  /// the frozen Python port reached it by running `/usr/bin/security` as a
  /// subprocess — which a sandboxed app cannot do, since the binary is not on
  /// the allowed surface. See the honesty note on [MacosSecretStore].
  Future<String?> keychainRead(String key);

  /// Stores [value] under [key], replacing whatever was there.
  Future<void> keychainWrite(String key, String value);

  /// Removes [key]. Removing a key that is not set is not an error.
  Future<void> keychainDelete(String key);

  /// The **names** of the keys this app has stored — never their values.
  ///
  /// Named separately from [keychainRead] rather than folded into it because a
  /// settings screen needs the first and must not be able to ask for the second
  /// by accident: one returns names, the other returns a secret, and a caller
  /// that wants "which routes are configured" should not have a method that
  /// hands it the API key while deciding.
  Future<List<String>> keychainKeys();
}

/// The panel's own rectangle and the screen it sits on.
final class PanelGeometry {
  const PanelGeometry({required this.screen, required this.window});

  final ScreenRect screen;
  final ScreenRect window;
}

/// What the native panel says, before it is reduced to the contract's three
/// events.
sealed class NativePanelEvent {
  const NativePanelEvent();
}

/// A finished drag: the whole rectangle, so the edge can be found from it.
final class NativePanelDragged extends NativePanelEvent {
  const NativePanelDragged({required this.window, required this.screen});

  final ScreenRect window;
  final ScreenRect screen;
}

final class NativePanelTapped extends NativePanelEvent {
  const NativePanelTapped(this.action);

  final String action;
}

final class NativePanelReadOnly extends NativePanelEvent {
  const NativePanelReadOnly(this.readOnly);

  final bool readOnly;
}

/// The real seam: one method channel, one event channel, one name.
///
/// The name is part of the contract between this Dart and the Swift beside it and
/// is asserted by `native_channel_test.dart`, because the failure mode of a
/// renamed method is a `MissingPluginException` at run time on a machine where
/// nobody is watching.
final class MethodChannelMacosNative implements MacosNative {
  MethodChannelMacosNative({
    MethodChannel? channel,
    EventChannel? events,
  })  : _channel = channel ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName);

  /// Shared with the Swift side. See `macos/Classes/MiaotouMacosPlugin.swift`.
  static const String methodChannelName = 'miaotoujunshi/macos';

  /// Events flow the other way, on their own channel, so a Dart-initiated call
  /// can never be mistaken for a window-initiated one.
  static const String eventChannelName = 'miaotoujunshi/macos/events';

  final MethodChannel _channel;
  final EventChannel _events;
  StreamController<NativePanelEvent>? _controller;

  @override
  Future<String?> findTargetWindow() async =>
      await _channel.invokeMethod<String>('findTargetWindow');

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    final Map<Object?, Object?>? reply =
        await _channel.invokeMapMethod<Object?, Object?>('capture', <String, Object?>{
      'windowId': targetWindowId,
    });
    if (reply == null) {
      return const CaptureFailed(code: 1, message: '截屏失败：原生层没有回答');
    }
    if (reply['ok'] != true) {
      return CaptureFailed(
        code: (reply['code'] as int?) ?? 1,
        message: (reply['message'] as String?) ?? '截屏失败',
      );
    }
    final Uint8List pixels = (reply['pixels']! as Uint8List);
    return CaptureOk(
      CaptureFrame(
        pixels: pixels,
        width: (reply['width']! as int),
        height: (reply['height']! as int),
        scaleX: (reply['scaleX']! as num).toDouble(),
        scaleY: (reply['scaleY']! as num).toDouble(),
        originX: (reply['originX']! as num).toDouble(),
        originY: (reply['originY']! as num).toDouble(),
      ),
    );
  }

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    final List<Object?>? reply = await _channel.invokeListMethod<Object?>(
      'recognize',
      <String, Object?>{
        'pixels': frame.pixels,
        'width': frame.width,
        'height': frame.height,
        'languages': languages,
      },
    );
    if (reply == null) {
      return const <OcrLine>[];
    }
    return <OcrLine>[
      for (final Object? raw in reply)
        () {
          final Map<Object?, Object?> line = raw! as Map<Object?, Object?>;
          return OcrLine(
            text: line['text']! as String,
            confidence: (line['confidence']! as num).toDouble(),
            bounds: ScreenRect(
              left: (line['left']! as num).toDouble(),
              top: (line['top']! as num).toDouble(),
              right: (line['right']! as num).toDouble(),
              bottom: (line['bottom']! as num).toDouble(),
            ),
          );
        }(),
    ];
  }

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async {
    final Map<Object?, Object?>? reply =
        await _channel.invokeMapMethod<Object?, Object?>('inject', <String, Object?>{
      'text': text,
      'windowId': target.windowId,
    });
    if (reply == null) {
      return const InjectResult.unverified('原生层没有回答');
    }
    if (reply['verified'] != true) {
      return InjectResult.unverified((reply['reason'] as String?) ?? '无法确认草稿是否落入');
    }
    return InjectResult.verified((reply['text'] as String?) ?? '');
  }

  @override
  Future<PanelGeometry> panelGeometry() async {
    final Map<Object?, Object?> reply =
        await _channel.invokeMapMethod<Object?, Object?>('panelGeometry') ??
            const <Object?, Object?>{};
    return PanelGeometry(
      screen: _rect(reply['screen']),
      window: _rect(reply['window']),
    );
  }

  @override
  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at}) async {
    await _channel.invokeMethod<void>('panel.show', <String, Object?>{
      'anchor': placement.anchor.name,
      'dx': placement.dx,
      'dy': placement.dy,
      // The size is stated even when the anchor is a corner, because the panel
      // starts collapsed and the native side has no way to know that: its own
      // default is the expanded window, and a first show that left it at
      // 420x620 would be a transparent rectangle over the chat taking clicks
      // meant for it (ADR-0020 decision 6).
      if (placement.width != null) 'width': placement.width,
      if (placement.height != null) 'height': placement.height,
      // `at` is a rectangle, and it crosses as one. It used to cross as four
      // loose numbers that the Swift then looked for under `window` and never
      // found, so a resolved free placement was silently dropped.
      if (at != null)
        'window': <String, Object?>{
          'left': at.left,
          'top': at.top,
          'right': at.right,
          'bottom': at.bottom,
        },
    });
  }

  @override
  Future<bool> hidePanel() async =>
      await _channel.invokeMethod<bool>('panel.hide') ?? false;

  @override
  Future<void> restorePanel() => _channel.invokeMethod<void>('panel.restore');

  @override
  Future<void> setPanelFocusable(bool value) =>
      _channel.invokeMethod<void>('panel.focusable', <String, Object?>{'value': value});

  @override
  Future<String> resourceRoot() async {
    // No `?? ''`. A missing answer becomes an empty string, and every caller
    // joins a path onto it — which yields `/…`, an absolute path out of the
    // filesystem root, rather than a path inside the bundle. The failure then
    // arrives as "no such file" from somewhere else entirely, naming a path the
    // application never intended to read. Answering the question wrongly is worse
    // than refusing it: the caller is a prompt, and this is a location the
    // platform is the only thing that knows.
    final String? root = await _channel.invokeMethod<String>('storage.resourceRoot');
    if (root == null || root.isEmpty) {
      throw StateError(
        'the platform gave no resource root, so there is nowhere to read the '
        'shared payload from; the build phase that copies it into the bundle is '
        'the thing to check (see ADR-0008)',
      );
    }
    return root;
  }

  @override
  Future<String> containerDirectory() async =>
      await _channel.invokeMethod<String>('storage.containerDirectory') ?? '';

  @override
  Future<String?> keychainRead(String key) =>
      _channel.invokeMethod<String>('keychain.read', <String, Object?>{'key': key});

  @override
  Future<void> keychainWrite(String key, String value) => _channel.invokeMethod<void>(
        'keychain.write',
        <String, Object?>{'key': key, 'value': value},
      );

  @override
  Future<void> keychainDelete(String key) =>
      _channel.invokeMethod<void>('keychain.delete', <String, Object?>{'key': key});

  @override
  Future<List<String>> keychainKeys() async =>
      await _channel.invokeListMethod<String>('keychain.keys') ?? const <String>[];

  @override
  Stream<NativePanelEvent> get events {
    _controller ??= _startListening();
    return _controller!.stream;
  }

  StreamController<NativePanelEvent> _startListening() {
    final StreamController<NativePanelEvent> controller =
        StreamController<NativePanelEvent>.broadcast();
    _controller = controller;
    _events.receiveBroadcastStream().listen(
      (Object? raw) {
        final Map<Object?, Object?> event = raw! as Map<Object?, Object?>;
        switch (event['kind'] as String?) {
          case 'dragged':
            controller.add(NativePanelDragged(
              window: _rect(event['window']),
              screen: _rect(event['screen']),
            ));
          case 'tapped':
            controller.add(NativePanelTapped(event['action']! as String));
          case 'readOnly':
            controller.add(NativePanelReadOnly(event['value'] == true));
        }
      },
      onError: controller.addError,
    );
    return controller;
  }

  static ScreenRect _rect(Object? raw) {
    if (raw is! Map) {
      return ScreenRect.empty;
    }
    return ScreenRect(
      left: (raw['left'] as num?)?.toDouble() ?? 0,
      top: (raw['top'] as num?)?.toDouble() ?? 0,
      right: (raw['right'] as num?)?.toDouble() ?? 0,
      bottom: (raw['bottom'] as num?)?.toDouble() ?? 0,
    );
  }
}
