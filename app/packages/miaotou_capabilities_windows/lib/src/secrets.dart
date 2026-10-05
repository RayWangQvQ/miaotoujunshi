import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

abstract interface class WindowsCredentialBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Set<String>> keys();
}

final class WindowsSecretStore implements SecretStore {
  WindowsSecretStore([WindowsCredentialBackend? backend])
    : _backend = backend ?? WindowsCredentialManager();

  final WindowsCredentialBackend _backend;

  @override
  Future<String?> read(String key) => _backend.read(key);

  @override
  Future<void> write(String key, String value) => _backend.write(key, value);

  @override
  Future<void> delete(String key) => _backend.delete(key);

  @override
  Future<Set<String>> keys() => _backend.keys();
}

final class WindowsCredentialManager implements WindowsCredentialBackend {
  static const String _prefix = 'miaotoujunshi/';
  static const int _generic = 1;
  static const int _persistLocalMachine = 2;
  static const int _notFound = 1168;
  static const int _maxBlobBytes = 2560;

  late final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');
  late final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');

  late final int Function(Pointer<_CredentialW>, int) _credWrite = _advapi
      .lookupFunction<
        Int32 Function(Pointer<_CredentialW>, Uint32),
        int Function(Pointer<_CredentialW>, int)
      >('CredWriteW');
  late final int Function(
    Pointer<Utf16>,
    int,
    int,
    Pointer<Pointer<_CredentialW>>,
  )
  _credRead = _advapi
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Pointer<_CredentialW>>,
        ),
        int Function(Pointer<Utf16>, int, int, Pointer<Pointer<_CredentialW>>)
      >('CredReadW');
  late final int Function(Pointer<Utf16>, int, int) _credDelete = _advapi
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Uint32, Uint32),
        int Function(Pointer<Utf16>, int, int)
      >('CredDeleteW');
  late final int Function(
    Pointer<Utf16>,
    int,
    Pointer<Uint32>,
    Pointer<Pointer<Pointer<_CredentialW>>>,
  )
  _credEnumerate = _advapi
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Pointer<Pointer<_CredentialW>>>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          Pointer<Uint32>,
          Pointer<Pointer<Pointer<_CredentialW>>>,
        )
      >('CredEnumerateW');
  late final void Function(Pointer<Void>) _credFree = _advapi
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('CredFree');
  late final int Function() _getLastError = _kernel
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  @override
  Future<String?> read(String key) async {
    _requireWindows();
    final Pointer<Utf16> target = _target(key).toNativeUtf16();
    final Pointer<Pointer<_CredentialW>> result =
        calloc<Pointer<_CredentialW>>();
    try {
      if (_credRead(target, _generic, 0, result) == 0) {
        if (_getLastError() == _notFound) {
          return null;
        }
        _fail('CredReadW', key);
      }
      final _CredentialW credential = result.value.ref;
      return utf8.decode(
        credential.credentialBlob.asTypedList(credential.credentialBlobSize),
      );
    } finally {
      if (result.value != nullptr) {
        _credFree(result.value.cast<Void>());
      }
      calloc.free(result);
      calloc.free(target);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _requireWindows();
    final List<int> bytes = utf8.encode(value);
    if (bytes.length > _maxBlobBytes) {
      throw ArgumentError.value(
        value,
        'value',
        'Credential Manager generic credentials are limited to '
            '$_maxBlobBytes bytes',
      );
    }
    final Pointer<_CredentialW> credential = calloc<_CredentialW>();
    final Pointer<Utf16> target = _target(key).toNativeUtf16();
    final Pointer<Uint8> blob = calloc<Uint8>(bytes.length);
    blob.asTypedList(bytes.length).setAll(0, bytes);
    try {
      credential.ref
        ..type = _generic
        ..targetName = target
        ..credentialBlobSize = bytes.length
        ..credentialBlob = blob
        ..persist = _persistLocalMachine
        ..userName = nullptr
        ..attributes = nullptr;
      if (_credWrite(credential, 0) == 0) {
        _fail('CredWriteW', key);
      }
    } finally {
      calloc.free(blob);
      calloc.free(target);
      calloc.free(credential);
    }
  }

  @override
  Future<void> delete(String key) async {
    _requireWindows();
    final Pointer<Utf16> target = _target(key).toNativeUtf16();
    try {
      if (_credDelete(target, _generic, 0) == 0 &&
          _getLastError() != _notFound) {
        _fail('CredDeleteW', key);
      }
    } finally {
      calloc.free(target);
    }
  }

  @override
  Future<Set<String>> keys() async {
    _requireWindows();
    final Pointer<Utf16> filter = '$_prefix*'.toNativeUtf16();
    final Pointer<Uint32> count = calloc<Uint32>();
    final Pointer<Pointer<Pointer<_CredentialW>>> result =
        calloc<Pointer<Pointer<_CredentialW>>>();
    try {
      if (_credEnumerate(filter, 0, count, result) == 0) {
        if (_getLastError() == _notFound) {
          return <String>{};
        }
        _fail('CredEnumerateW', '*');
      }
      return <String>{
        for (int index = 0; index < count.value; index++)
          result.value[index].ref.targetName.toDartString().substring(
            _prefix.length,
          ),
      };
    } finally {
      if (result.value != nullptr) {
        _credFree(result.value.cast<Void>());
      }
      calloc.free(result);
      calloc.free(count);
      calloc.free(filter);
    }
  }

  static String _target(String key) {
    if (key.trim().isEmpty || key.contains('/') || key.contains(r'\')) {
      throw ArgumentError.value(
        key,
        'key',
        'must be a non-empty Credential Manager account name',
      );
    }
    return '$_prefix$key';
  }

  static void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Windows Credential Manager is only available on Windows',
      );
    }
  }

  Never _fail(String operation, String key) => throw FileSystemException(
    '$operation failed for Credential Manager key $key '
    '(Windows error ${_getLastError()})',
  );
}

final class _FileTime extends Struct {
  @Uint32()
  external int low;

  @Uint32()
  external int high;
}

final class _CredentialW extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  external _FileTime lastWritten;

  @Uint32()
  external int credentialBlobSize;

  external Pointer<Uint8> credentialBlob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}
