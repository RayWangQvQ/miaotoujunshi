import 'package:miaotou_domain/miaotou_domain.dart';

/// What the main window's pages have to show.
///
/// Everything here is nullable, and null means "nothing has happened yet"
/// rather than "nothing was found": the shell starts before a conversation has
/// been read, and the pages answer that state in words instead of rendering an
/// empty chart or an empty card.
///
/// It is a plain immutable value rather than a `ChangeNotifier` because #11
/// builds the shell, not the pipeline that fills it. When the capture loop and
/// the panel arrive (#15/#19/#23 and #12) this becomes observable, and the pages
/// will not change — which is the point of giving them their content as a
/// parameter instead of letting them go and look for it.
final class ShellContent {
  const ShellContent({
    this.advice,
    this.trend,
    this.trendRules,
    this.profile,
  });

  /// The last analysis, or null when there has not been one.
  final Advice? advice;

  final Trend? trend;

  /// The CSV contract the trend was read under. Held beside the trend because
  /// the trend view cannot draw without its `metric_note`, and the note is a
  /// property of the contract rather than of the data.
  final TrendRules? trendRules;

  final Profile? profile;

  /// The state the application starts in.
  static const ShellContent empty = ShellContent();
}
