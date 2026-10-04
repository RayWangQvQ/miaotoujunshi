import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

abstract interface class SharedFrameReader {
  Uint8List read(String mappingName, int byteLength);
}

/// Reads the bridge's named file mapping without sending frame bytes through
/// the command pipe.
final class WindowsSharedFrameReader implements SharedFrameReader {
  WindowsSharedFrameReader({DynamicLibrary? kernel32})
    : _kernel32 =
          kernel32 ??
          (Platform.isWindows
              ? DynamicLibrary.open('kernel32.dll')
              : throw UnsupportedError(
                  'Windows shared memory is only available on Windows',
                )) {
    _open = _kernel32.lookupFunction<_OpenNative, _Open>('OpenFileMappingW');
    _map = _kernel32.lookupFunction<_MapNative, _Map>('MapViewOfFile');
    _unmap = _kernel32.lookupFunction<_UnmapNative, _Unmap>('UnmapViewOfFile');
    _close = _kernel32.lookupFunction<_CloseNative, _Close>('CloseHandle');
  }

  static const int _fileMapRead = 0x0004;

  final DynamicLibrary _kernel32;
  late final _Open _open;
  late final _Map _map;
  late final _Unmap _unmap;
  late final _Close _close;

  @override
  Uint8List read(String mappingName, int byteLength) {
    if (byteLength <= 0) {
      throw ArgumentError.value(byteLength, 'byteLength');
    }
    final Pointer<Utf16> name = mappingName.toNativeUtf16();
    final int handle;
    try {
      handle = _open(_fileMapRead, 0, name);
    } finally {
      calloc.free(name);
    }
    if (handle == 0) {
      throw StateError('could not open shared frame $mappingName');
    }
    final Pointer<Void> view = _map(handle, _fileMapRead, 0, 0, byteLength);
    if (view == nullptr) {
      _close(handle);
      throw StateError('could not map shared frame $mappingName');
    }
    try {
      return Uint8List.fromList(view.cast<Uint8>().asTypedList(byteLength));
    } finally {
      _unmap(view);
      _close(handle);
    }
  }
}

typedef _OpenNative = IntPtr Function(Uint32, Int32, Pointer<Utf16>);
typedef _Open = int Function(int, int, Pointer<Utf16>);
typedef _MapNative = Pointer<Void> Function(
  IntPtr,
  Uint32,
  Uint32,
  Uint32,
  IntPtr,
);
typedef _Map = Pointer<Void> Function(int, int, int, int, int);
typedef _UnmapNative = Int32 Function(Pointer<Void>);
typedef _Unmap = int Function(Pointer<Void>);
typedef _CloseNative = Int32 Function(IntPtr);
typedef _Close = int Function(int);
