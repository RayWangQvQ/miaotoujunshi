import 'package:miaotou_domain/miaotou_domain.dart';
import 'package:test/test.dart';

/// Two ports had version checks; all of them deferred the comparison to a
/// later hand-off and none of them agreed about what "newer" means. The
/// domain here owns the comparison and the dev-version skip; the wire stays
/// in the app, exactly the way [ModelTransport] does.
void main() {
  group('Version.tryParse', () {
    test('parses a dotted numeric tag', () {
      expect(Version.tryParse('1.2.3')?.segments, <int>[1, 2, 3]);
    });

    test('refuses a tag with a non-numeric segment', () {
      expect(Version.tryParse('0.0.0-dev'), isNull);
      expect(Version.tryParse('dev'), isNull);
      expect(Version.tryParse('1.2.x'), isNull);
    });

    test('refuses an empty segment', () {
      expect(Version.tryParse('1..2'), isNull);
    });
  });

  group('Version.isStrictlyOlderThan', () {
    test('newer at the third segment wins', () {
      expect(
        Version.tryParse('1.2.3')!.isStrictlyOlderThan(Version.tryParse('1.2.4')!),
        isTrue,
      );
    });

    test('newer at the second segment wins even with a longer current', () {
      expect(
        Version.tryParse('1.9.9')!.isStrictlyOlderThan(Version.tryParse('2.0')!),
        isTrue,
      );
    });

    test('two equal versions are not updates for each other', () {
      final Version v = Version.tryParse('1.0.0')!;
      expect(v.isStrictlyOlderThan(v), isFalse);
    });

    test('a longer but equal release is the same, not newer', () {
      // 1.2 and 1.2.0 are the same release post-padded.
      final Version shorter = Version.tryParse('1.2')!;
      final Version padded = Version.tryParse('1.2.0')!;
      expect(shorter.isStrictlyOlderThan(padded), isFalse);
      expect(padded.isStrictlyOlderThan(shorter), isFalse);
    });

    test('a longer release with a non-zero extra segment is newer', () {
      expect(
        Version.tryParse('1.2')!.isStrictlyOlderThan(Version.tryParse('1.2.1')!),
        isTrue,
      );
    });
  });

  group('newerRelease', () {
    test('reports a strictly-newer release', () {
      final ReleaseInfo result = newerRelease(
        current: '1.0.0',
        latest: const ReleaseInfo(tag: '9.9.9', url: 'https://x/release'),
      )!;
      expect(result.tag, '9.9.9');
      expect(result.url, 'https://x/release');
    });

    test('stays silent when the running version is the release', () {
      expect(
        newerRelease(
          current: '1.0.0',
          latest: const ReleaseInfo(tag: '1.0.0', url: 'https://x'),
        ),
        isNull,
      );
    });

    test('stays silent when the running version is newer than the release', () {
      expect(
        newerRelease(
          current: '1.5.0',
          latest: const ReleaseInfo(tag: '1.0.0', url: 'https://x'),
        ),
        isNull,
      );
    });

    test('stays silent for a development build', () {
      expect(
        newerRelease(
          current: '0.0.0-dev',
          latest: const ReleaseInfo(tag: '9.9.9', url: 'https://x'),
        ),
        isNull,
        reason: 'a person running from source is never asked to update; '
            'dev builds do not parse and the check is a no-op for them',
      );
    });

    test('stays silent when the fetch produced no release', () {
      expect(
        newerRelease(current: '1.0.0', latest: null),
        isNull,
      );
    });

    test('stays silent when the fetched tag does not parse', () {
      // A release tagged with a non-numeric form is not a release the check
      // can reason about; reporting it would advertise a version without a
      // way to compare.
      expect(
        newerRelease(
          current: '1.0.0',
          latest: const ReleaseInfo(tag: 'dev', url: 'https://x'),
        ),
        isNull,
      );
    });

    test('strips a leading v from a tag before parsing', () {
      // GitHub returns `v1.2.3`; the app strips the leading `v` and asks
      // the comparison. The current strip is the app's concern; the domain
      // sees the tag the app hands it.
      final String stripped = stripLeadingV('v1.0.0');
      expect(stripped, '1.0.0');
      expect(
        Version.tryParse(stripped)?.segments,
        <int>[1, 0, 0],
      );
    });
  });

  group('GitHub tag spelling', () {
    test('stripping is idempotent on a tag without the prefix', () {
      expect(stripLeadingV('1.2.3'), '1.2.3');
    });
  });
}