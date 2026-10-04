// The update check — one implementation for all three ports.
//
// Each of the three ports had its own version-check before the migration;
// none of them was the same. This module is the part that is *not* a cable
// detail: parsing a release tag, parsing the running version, and deciding
// whether the latest release is strictly newer. The network fetch that
// produces the latest release is a cable detail and lives in the application,
// exactly the way [ModelTransport] does — the domain declares the shape, the
// app provides the wire (ADR-0009).
//
// ## What "strictly newer" means
//
// Two parsed versions are compared element by element; the first differing
// segment decides. `1.2.3 < 1.2.4`, `1.2.3 < 1.3`, `1.9 < 2.0`. A version
// that does not parse to a dot-separated list of digits is a development
// build ("0.0.0-dev", "dev") and the check is a **no-op** for it: a person
// running from source is not nagged, and a person running a tagged release is.
//
// ## Why the wire stays out
//
// The Windows port hit GitHub's API and returned `None` for any failure —
// offline, rate-limited, behind a GFW, malformed JSON. That is the right
// failure mode for the user (silence, not a crash), and it belongs at the
// wire, not in the comparison. The domain here never sees a network: it sees
// the release the app fetched, or the absence of one.

/// A version that parsed, or the absence of one.
///
/// `null` is "not a release version" — the running build is a dev build, or the
/// fetched tag was malformed — and the check reports nothing for it.
final class Version {
  const Version(this.segments);

  /// `"1.2.3"` → `Version([1, 2, 3])`. Any non-digit segment returns `null`,
  /// so `"0.0.0-dev"` and `"dev"` both decline the comparison rather than
  /// being misread.
  static Version? tryParse(String raw) {
    final List<String> segs = raw.split('.');
    if (segs.isEmpty) {
      return null;
    }
    final List<int> parsed = <int>[];
    for (final String seg in segs) {
      if (seg.isEmpty || !seg.codeUnits.every(_isAsciiDigit)) {
        return null;
    }
      parsed.add(int.parse(seg));
    }
    return Version(parsed);
  }

  final List<int> segments;

  /// True when [other] is newer at the first segment that differs. Comparing
  /// different lengths — `1.2` vs `1.2.0` — treats the shorter as the
  /// missing-zero form, so they are equal: a release tagged `1.2` and one
  /// tagged `1.2.0` are not reported as updates to each other.
  bool isStrictlyOlderThan(Version other) {
    final int length =
        segments.length < other.segments.length ? segments.length : other.segments.length;
    for (int i = 0; i < length; i++) {
      if (segments[i] != other.segments[i]) {
        return segments[i] < other.segments[i];
      }
    }
    // Equal on the shared prefix. A longer other with non-zero extra segments
    // wins; a longer other with only zeros is the same release.
    if (other.segments.length > segments.length) {
      return other.segments.skip(segments.length).any((int seg) => seg != 0);
    }
    return false;
  }
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// One fetched release: its tag (without the leading `v`) and its page URL.
final class ReleaseInfo {
  const ReleaseInfo({required this.tag, required this.url});

  /// The release tag with a leading `v` already stripped, matching the form
  /// [Version.tryParse] expects.
  final String tag;

  /// The release's HTML URL, to offer the user a one-tap link.
  final String url;
}

/// Decides whether the user should be told about a newer release.
///
/// Returns the release to report when [latest] is strictly newer than
/// [current]; returns `null` when either side is a dev version, the
/// fetched release is not newer, or the app reported no release at all.
///
/// Pure, synchronous and side-effect free: the caller handles the network and
/// the UI. A development build ([current] does not parse) returns `null`
/// without inspecting [latest], so a person running from source is never
/// asked to update.
ReleaseInfo? newerRelease({
  required String current,
  required ReleaseInfo? latest,
}) {
  final Version? cur = Version.tryParse(current);
  if (cur == null) {
    return null;
  }
  if (latest == null) {
    return null;
  }
  final Version? lat = Version.tryParse(latest.tag);
  if (lat == null) {
    return null;
  }
  return cur.isStrictlyOlderThan(lat) ? latest : null;
}

/// Strips a leading `v` from a release tag, the form GitHub publishes.
///
/// `"v1.2.3"` → `"1.2.3"`. A tag without the prefix is returned unchanged, so
/// the function is safe to apply to whatever `tag_name` the API returned.
String stripLeadingV(String tag) =>
    tag.startsWith('v') ? tag.substring(1) : tag;