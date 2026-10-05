import 'dart:convert';
import 'dart:io';

final class WindowsJsonFile {
  WindowsJsonFile(Directory directory, this.fileName)
    : _directory = (() => directory);

  factory WindowsJsonFile.inApplicationData(String fileName) =>
      WindowsJsonFile._(_applicationDataDirectory, fileName);

  WindowsJsonFile._(this._directory, this.fileName);

  final Directory Function() _directory;
  final String fileName;

  Directory get directory => _directory();

  File get file => File('${directory.path}${Platform.pathSeparator}$fileName');

  Future<Map<String, Object?>> read() async {
    if (!file.existsSync()) {
      return <String, Object?>{};
    }
    final String text = file.readAsStringSync(encoding: utf8);
    if (text.trim().isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw FormatException(
        '$fileName does not hold a JSON object; refusing to hide data loss',
        file.path,
      );
    }
    return decoded.cast<String, Object?>();
  }

  Future<void> write(Map<String, Object?> contents) async {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final File scratch = File('${file.path}.tmp');
    scratch.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(contents),
      encoding: utf8,
      flush: true,
    );
    scratch.renameSync(file.path);
  }

  static Directory _applicationDataDirectory() {
    final String? appData =
        Platform.environment['APPDATA'] ?? Platform.environment['LOCALAPPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      throw StateError(
        'Windows did not provide APPDATA or LOCALAPPDATA; persistent storage '
        'cannot be placed safely',
      );
    }
    return Directory('$appData${Platform.pathSeparator}miaotoujunshi');
  }
}
