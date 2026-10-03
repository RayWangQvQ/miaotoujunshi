/// The half of the application that decides, with no dependency on any platform.
///
/// ADR-0009 splits the application in two. Below the contract sit the three
/// platform implementations, which differ per port and are allowed to. Above it
/// sits this package, which must **not** differ per port at all — and the way
/// that is enforced is that it *cannot* reach a platform: it depends on
/// `miaotou_capabilities` and on nothing else, imports no Flutter library and no
/// `dart:io`, and therefore runs under `dart test` in milliseconds, on any
/// machine, with no device attached.
///
/// ## What is here
///
/// * **#7 — judging, prompt assembly and candidate scoring.** Landed:
///   [Snapshot] and the transcript it renders, [ReplyPreferences],
///   [SharedVocabulary] and [SceneMaterial], the reply/rewrite/strategy prompts,
///   [parseJevDecision] / [parseDeepSeekDecision] / [parseChoice],
///   [parseAdvice] / [parseRewrite], [applyScores] / [rankCandidates], and the
///   two entry points that put them in order: [analyzeSnapshot] and
///   [rewriteSnapshot].
/// * **#8** — trend and K-line data, and CSV handling. Landed: [Candle] and
///   [Trend] in macOS's superset shape, [TrendRules] read from the payload's own
///   contract file, [readChatCsv] for the import every port had, [writeCandleCsv]
///   and [readCandleCsv] for the export none of them had, the synthetic case
///   bundle, and the RFC 4180 [parseCsvGrid] / [writeCsvGrid] the two directions
///   share. Rendering strings are deliberately **not** here: #11 owns the copy.
/// * **#9 — the knowledge base's logic and the memory store's used subset
///   (ADR-0010).** Landed: [RelationshipVocabulary] and [Profile], the
///   [validateProfile] / [profileContext] / [buildBackground] trio lifted from
///   macOS's `experience.py`, and the [diffProfile] / [applySave] / [undoSave]
///   loop that is the only part of the old `MemoryBridge` worth porting line
///   for line. `Conversations` and `AutoGate` are not here: they are
///   conversation identity, which #12 owns.
/// * **#10** — the anti-injection filter, scenario selection and the update
///   check. Not yet.
/// * **#12** — conversation identity and the read-only derivation, which ADR-0002
///   puts on the domain side of the panel rather than inside it. Not yet, and it
///   is where [Snapshot]'s identity hash belongs.
///
/// ## The one thing worth knowing before adding to it
///
/// A member that needs a platform is a member that belongs behind the contract
/// instead. That pressure is the point of the split, and the dependency-direction
/// test in `test/` is what makes it more than a comment.
///
/// There is **one** exception, and it is deliberate: [ModelTransport]. It is not
/// an eleventh capability — it is not something one platform can do and another
/// cannot — so it is declared here and implemented by the application, which is
/// what keeps the network, the credentials and the redirect policy out of this
/// package while still letting [analyzeSnapshot] run the whole judgement. See
/// `src/model_gateway.dart`.
library;

export 'src/advice.dart';
export 'src/analysis.dart';
export 'src/csv.dart';
export 'src/errors.dart';
export 'src/judging.dart';
export 'src/memory.dart';
export 'src/model_gateway.dart';
export 'src/preferences.dart';
export 'src/prompts.dart';
export 'src/relationship.dart';
export 'src/rendering.dart';
export 'src/scoring.dart';
export 'src/shared_material.dart';
export 'src/snapshot.dart';
export 'src/strategy.dart';
export 'src/trend.dart';
