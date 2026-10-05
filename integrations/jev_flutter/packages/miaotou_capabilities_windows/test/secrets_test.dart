import 'dart:io';

import 'package:test/test.dart';

void main() {
  final String source = File('lib/src/secrets.dart').readAsStringSync();

  test('credentials use Credential Manager generic credentials', () {
    for (final String api in <String>[
      'CredReadW',
      'CredWriteW',
      'CredDeleteW',
      'CredEnumerateW',
      'CredFree',
    ]) {
      expect(source, contains(api));
    }
    expect(source, contains('_generic = 1'));
    expect(source, contains('_persistLocalMachine = 2'));
  });

  test(
    'the credential implementation never reaches the registry or a file',
    () {
      final String code = source
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('RegOpen')));
      expect(code, isNot(contains('RegSet')));
      expect(code, isNot(contains('File(')));
      expect(code, isNot(contains('Process.')));
    },
  );
}
