import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';

import 'panel_exclusion.dart';
import 'shared_memory.dart';

/// The single out-of-process Windows seam from ADR-0013.
abstract interface class WindowsNative {
  Future<String?> findTargetWindow();

  Future<CaptureOutcome> capture({String? targetWindowId});

  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  });

  Future<InjectResult> inject(String text, {required InjectTarget target});
}

/// One request/response exchange with the bridge.
abstract interface class WindowsBridgeRpc {
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]);

  Future<void> close();
}

/// A bridge process disappeared or could not be started.
final class WindowsBridgeUnavailable implements Exception {
  const WindowsBridgeUnavailable(this.message);

  final String message;

  @override
  String toString() => 'Windows bridge unavailable: $message';
}

/// Production implementation of the Windows seam.
///
/// JSON carries commands and frame metadata only. The raw BGRA frame lives in a
/// named file mapping owned by the bridge; [SharedFrameReader] maps that region
/// and makes the one copy required by the capability contract's [Uint8List].
final class ProcessWindowsNative implements WindowsNative {
  ProcessWindowsNative({
    WindowsBridgeRpc? rpc,
    PanelExclusion? panelExclusion,
    SharedFrameReader? sharedMemory,
  }) : _rpc = rpc ?? StdioWindowsBridgeRpc(),
       _panelExclusion =
           panelExclusion ??
           (Platform.isWindows ? WindowsPanelExclusion() : null) {
    _sharedMemory = sharedMemory;
  }

  final WindowsBridgeRpc _rpc;
  final PanelExclusion? _panelExclusion;
  SharedFrameReader? _sharedMemory;
  final Expando<int> _generations = Expando<int>(
    'Windows shared-frame generation',
  );

  @override
  Future<String?> findTargetWindow() async {
    final Map<String, Object?> reply = await _rpc.call('window.findTarget');
    return reply['windowId'] as String?;
  }

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    try {
      _panelExclusion?.excludeCurrentProcessWindows();
    } on Object catch (error) {
      throw WindowsBridgeUnavailable('could not exclude the app panel: $error');
    }
    final Map<String, Object?> reply = await _rpc.call(
      'capture.latest',
      <String, Object?>{'windowId': targetWindowId},
    );
    if (reply['captured'] == false) {
      return CaptureFailed(
        code: (reply['code'] as num?)?.toInt() ?? 1,
        message: (reply['message'] as String?) ?? '截屏失败',
      );
    }

    final String mapping = _requiredString(reply, 'mapping');
    final int byteLength = _requiredInt(reply, 'byteLength');
    final Uint8List pixels = (_sharedMemory ??= WindowsSharedFrameReader())
        .read(mapping, byteLength);
    if (pixels.length != byteLength) {
      throw StateError(
        'shared frame $mapping declared $byteLength bytes but exposed '
        '${pixels.length}',
      );
    }
    final CaptureFrame frame = CaptureFrame(
      pixels: pixels,
      width: _requiredInt(reply, 'width'),
      height: _requiredInt(reply, 'height'),
      scaleX: _requiredDouble(reply, 'scaleX'),
      scaleY: _requiredDouble(reply, 'scaleY'),
      originX: _requiredDouble(reply, 'originX'),
      originY: _requiredDouble(reply, 'originY'),
    );
    _generations[frame] = _requiredInt(reply, 'generation');
    return CaptureOk(frame);
  }

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    final int? generation = _generations[frame];
    if (generation == null) {
      throw StateError(
        'Windows OCR can only read a frame produced by the Windows bridge; '
        'sending pixels back over IPC would defeat the shared-memory boundary',
      );
    }
    final Map<String, Object?> reply = await _rpc.call(
      'ocr.recognize',
      <String, Object?>{'generation': generation, 'languages': languages},
    );
    final Object? rawLines = reply['lines'];
    if (rawLines is! List<Object?>) {
      throw StateError('the Windows bridge returned no OCR line list');
    }
    return <OcrLine>[
      for (final Object? raw in rawLines)
        () {
          if (raw is! Map<Object?, Object?>) {
            throw StateError(
              'the Windows bridge returned a malformed OCR line',
            );
          }
          return OcrLine(
            text: _requiredString(raw, 'text'),
            confidence: _requiredDouble(raw, 'confidence'),
            bounds: ScreenRect(
              left: _requiredDouble(raw, 'left'),
              top: _requiredDouble(raw, 'top'),
              right: _requiredDouble(raw, 'right'),
              bottom: _requiredDouble(raw, 'bottom'),
            ),
          );
        }(),
    ];
  }

  @override
  Future<InjectResult> inject(
    String text, {
    required InjectTarget target,
  }) async {
    try {
      final Map<String, Object?> reply = await _rpc.call(
        'input.inject',
        <String, Object?>{'windowId': target.windowId, 'text': text},
      );
      if (reply['verified'] != true) {
        return InjectResult.unverified(
          (reply['reason'] as String?) ?? '无法确认草稿是否落入',
        );
      }
      return InjectResult.verified((reply['observedText'] as String?) ?? '');
    } on WindowsBridgeUnavailable catch (error) {
      return InjectResult.unverified(error.message);
    }
  }

  Future<void> close() => _rpc.close();
}

/// Newline-delimited JSON transport for the helper executable.
///
/// The helper is restarted lazily after an exit. Every request pending at the
/// time of the exit receives [WindowsBridgeUnavailable], which keeps a native
/// fault from becoming a Flutter-process fault.
final class StdioWindowsBridgeRpc implements WindowsBridgeRpc {
  StdioWindowsBridgeRpc({String? executable, ProcessStarter? startProcess})
    : _executable = executable ?? _defaultExecutable(),
      _startProcess = startProcess ?? Process.start;

  static const int protocolVersion = 1;

  final String _executable;
  final ProcessStarter _startProcess;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};

  Process? _process;
  Future<Process>? _starting;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  int _nextId = 1;
  String _lastStderr = '';

  @override
  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final Process process = await _ensureStarted();
    final int id = _nextId++;
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _pending[id] = completer;
    try {
      process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'method': method,
          'arguments': arguments,
        }),
      );
      await process.stdin.flush();
    } on Object catch (error) {
      _pending.remove(id);
      _bridgeExited('could not write request: $error');
      throw WindowsBridgeUnavailable('could not write request: $error');
    }
    return completer.future;
  }

  Future<Process> _ensureStarted() async {
    final Process? running = _process;
    if (running != null) {
      return running;
    }
    final Future<Process>? inFlight = _starting;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<Process> start = _start();
    _starting = start;
    try {
      return await start;
    } finally {
      _starting = null;
    }
  }

  Future<Process> _start() async {
    if (!Platform.isWindows) {
      throw const WindowsBridgeUnavailable(
        'the Windows bridge can only start on Windows',
      );
    }
    final Process process;
    try {
      process = await _startProcess(_executable, <String>[
        '--stdio',
        '--protocol=$protocolVersion',
      ], mode: ProcessStartMode.normal);
    } on ProcessException catch (error) {
      throw WindowsBridgeUnavailable(error.message);
    }
    _process = process;
    _lastStderr = '';
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleLine,
          onError: (Object error) {
            _bridgeExited('stdout failed: $error');
          },
        );
    _stderr = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          _lastStderr = line.length <= 300
              ? line
              : line.substring(line.length - 300);
        });
    unawaited(
      process.exitCode.then((int code) {
        _bridgeExited(
          'process exited with code $code'
          '${_lastStderr.isEmpty ? '' : ': $_lastStderr'}',
        );
      }),
    );
    return process;
  }

  void _handleLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _bridgeExited('bridge wrote malformed JSON');
      return;
    }
    if (decoded is! Map<String, Object?>) {
      _bridgeExited('bridge wrote a non-object response');
      return;
    }
    final int? id = (decoded['id'] as num?)?.toInt();
    final Completer<Map<String, Object?>>? pending = _pending.remove(id);
    if (pending == null) {
      return;
    }
    if (decoded['ok'] != true) {
      pending.completeError(
        WindowsBridgeUnavailable(
          (decoded['error'] as String?) ?? 'bridge request failed',
        ),
      );
      return;
    }
    final Object? result = decoded['result'];
    if (result is! Map<String, Object?>) {
      pending.completeError(
        const WindowsBridgeUnavailable('bridge returned no result object'),
      );
      return;
    }
    pending.complete(result);
  }

  void _bridgeExited(String reason) {
    _process = null;
    final WindowsBridgeUnavailable error = WindowsBridgeUnavailable(reason);
    for (final Completer<Map<String, Object?>> completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  @override
  Future<void> close() async {
    final Process? process = _process;
    _process = null;
    await _stdout?.cancel();
    await _stderr?.cancel();
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
    _bridgeExited('bridge closed');
  }

  static String _defaultExecutable() {
    final String? override = Platform.environment['MIAOTOU_WINDOWS_BRIDGE'];
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}miaotou_bridge.exe';
  }
}

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  ProcessStartMode mode,
});

String _requiredString(Map<Object?, Object?> value, String key) {
  final Object? result = value[key];
  if (result is! String || result.isEmpty) {
    throw StateError('the Windows bridge omitted $key');
  }
  return result;
}

int _requiredInt(Map<Object?, Object?> value, String key) {
  final Object? result = value[key];
  if (result is! num) {
    throw StateError('the Windows bridge omitted $key');
  }
  return result.toInt();
}

double _requiredDouble(Map<Object?, Object?> value, String key) {
  final Object? result = value[key];
  if (result is! num) {
    throw StateError('the Windows bridge omitted $key');
  }
  return result.toDouble();
}
