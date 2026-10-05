import 'package:flutter/services.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';

/// The Android permission operations below the [Permissions] contract.
///
/// The seam exists for the same reason the panel's and the ingest's do: the
/// contract's own tests must be able to drive this port without a device, and
/// the Kotlin half must be reachable from a test with a scripted channel rather
/// than a real Android system.
abstract interface class AndroidPermissionNative {
  Future<PermissionReport> readPermissions();

  Future<void> openPermissionSettings(PermissionKind kind);
}

/// The method-channel seam implemented by `AndroidPermissionsHost.kt`.
///
/// **Both vocabularies on the wire are the Dart enums' own names.** `off`,
/// `inactive` and `ready` are [PermissionState.name]; `accessibility` and
/// `overlay` are [PermissionKind.name]. Nothing is translated, so there is no
/// second spelling to drift — and a state Kotlin invents that Dart does not know
/// is a [FormatException] rather than a silent `off`, which is the one answer
/// that would read as "you never granted it" when the truth is "this build does
/// not understand the answer".
final class MethodChannelAndroidPermissionNative
    implements AndroidPermissionNative {
  MethodChannelAndroidPermissionNative({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'miaotoujunshi/android/permissions';

  final MethodChannel _channel;

  @override
  Future<PermissionReport> readPermissions() async {
    final Map<Object?, Object?> raw = _map(
      await _channel.invokeMethod<Object?>('read'),
      'permission report',
    );
    return PermissionReport(
      accessibility: _state(raw, 'accessibility'),
      overlay: _state(raw, 'overlay'),
    );
  }

  @override
  Future<void> openPermissionSettings(PermissionKind kind) =>
      _channel.invokeMethod<void>('open', <String, Object?>{'kind': kind.name});

  static PermissionState _state(Map<Object?, Object?> report, String key) {
    final Object? value = report[key];
    return PermissionState.values.firstWhere(
      (PermissionState candidate) => candidate.name == value,
      orElse: () =>
          throw FormatException('unknown permission state "$value" for $key'),
    );
  }

  static Map<Object?, Object?> _map(Object? value, String name) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$name must be a map');
    }
    return value;
  }
}
