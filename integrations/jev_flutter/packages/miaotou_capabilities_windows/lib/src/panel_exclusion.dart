import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _EnumWindowsProcNative = Int32 Function(IntPtr window, IntPtr context);
typedef _EnumWindowsNative = Int32 Function(
  Pointer<NativeFunction<_EnumWindowsProcNative>> callback,
  IntPtr context,
);
typedef _EnumWindowsDart = int Function(
  Pointer<NativeFunction<_EnumWindowsProcNative>> callback,
  int context,
);
typedef _GetWindowThreadProcessIdNative = Uint32 Function(
  IntPtr window,
  Pointer<Uint32> processId,
);
typedef _GetWindowThreadProcessIdDart = int Function(
  int window,
  Pointer<Uint32> processId,
);
typedef _IsWindowVisibleNative = Int32 Function(IntPtr window);
typedef _IsWindowVisibleDart = int Function(int window);
typedef _SetWindowDisplayAffinityNative = Int32 Function(
  IntPtr window,
  Uint32 affinity,
);
typedef _SetWindowDisplayAffinityDart = int Function(int window, int affinity);

const int _wdaExcludeFromCapture = 0x11;

DynamicLibrary? _user32Library;
DynamicLibrary get _user32 =>
    _user32Library ??= DynamicLibrary.open('user32.dll');
_GetWindowThreadProcessIdDart get _getWindowThreadProcessId =>
    _user32.lookupFunction<
      _GetWindowThreadProcessIdNative,
      _GetWindowThreadProcessIdDart
    >('GetWindowThreadProcessId');
_IsWindowVisibleDart get _isWindowVisible =>
    _user32.lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>(
      'IsWindowVisible',
    );
_SetWindowDisplayAffinityDart get _setWindowDisplayAffinity =>
    _user32.lookupFunction<
      _SetWindowDisplayAffinityNative,
      _SetWindowDisplayAffinityDart
    >('SetWindowDisplayAffinity');

int _excludeOwnedWindow(int window, int rawContext) {
  final Pointer<Uint32> context = Pointer<Uint32>.fromAddress(rawContext);
  final Pointer<Uint32> owner = calloc<Uint32>();
  try {
    _getWindowThreadProcessId(window, owner);
    if (owner.value != context[0] || _isWindowVisible(window) == 0) {
      return 1;
    }
    context[1]++;
    if (_setWindowDisplayAffinity(window, _wdaExcludeFromCapture) == 0) {
      context[2]++;
    }
    return 1;
  } finally {
    calloc.free(owner);
  }
}

final Pointer<NativeFunction<_EnumWindowsProcNative>>
_excludeOwnedWindowPointer = Pointer.fromFunction<_EnumWindowsProcNative>(
  _excludeOwnedWindow,
  0,
);

abstract interface class PanelExclusion {
  void excludeCurrentProcessWindows();
}

/// Excludes Flutter-owned top-level windows from desktop and window capture.
///
/// `SetWindowDisplayAffinity` must run in the process that owns the window, so
/// this deliberately lives on the Dart side rather than in the bridge.
final class WindowsPanelExclusion implements PanelExclusion {
  WindowsPanelExclusion()
    : _enumWindows = _user32
          .lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');

  final _EnumWindowsDart _enumWindows;

  @override
  void excludeCurrentProcessWindows() {
    if (!Platform.isWindows) {
      return;
    }
    final Pointer<Uint32> context = calloc<Uint32>(3);
    try {
      context[0] = pid;
      if (_enumWindows(_excludeOwnedWindowPointer, context.address) == 0) {
        throw StateError('could not enumerate Flutter windows');
      }
      if (context[1] == 0) {
        throw StateError('no visible Flutter window was found for exclusion');
      }
      if (context[2] != 0) {
        throw StateError(
          'could not exclude ${context[2]} of ${context[1]} Flutter windows',
        );
      }
    } finally {
      calloc.free(context);
    }
  }
}
