/// The half of the application that decides, with no dependency on any platform.
///
/// ADR-0009 splits the application in two. Below the contract sit the three
/// platform implementations, which differ per port and are allowed to. Above it
/// sits this package, which must not differ per port at all — and the way that is
/// enforced is that it *cannot* reach a platform: it depends on
/// `miaotou_capabilities` and on nothing else, imports no Flutter library and no
/// `dart:io`, and therefore runs under `dart test` in milliseconds, on any
/// machine, with no device attached.
///
/// **This library is deliberately empty at the skeleton milestone.** What will
/// live here is named by the tickets that build it, and stating it here keeps the
/// boundary legible while the code arrives:
///
/// * **#7** — judging, prompt assembly and candidate scoring.
/// * **#8** — trend and K-line data, and CSV handling.
/// * **#9** — the knowledge base's logic and the memory store's used subset
///   (ADR-0010), including the profile diff that makes `MemoryStore.undo` revert
///   exactly this run's writes.
/// * **#10** — the anti-injection filter, scenario selection and the update check.
/// * **#12** — conversation identity and the read-only derivation, which ADR-0002
///   puts on the domain side of the panel rather than inside it.
///
/// The one thing worth knowing before adding to it: a member that needs a
/// platform is a member that belongs behind the contract instead. That pressure is
/// the point of the split, and the dependency-direction test in `test/` is what
/// makes it more than a comment.
library;
