/// A scripted macOS, for tests on the other side of the seam.
///
/// The same reasoning as `miaotou_capabilities`' own `testing.dart`, one level
/// up: the seam exists so that everything above it can be exercised with no Mac
/// attached, and a fake that lived in this package's `test/` directory could not
/// be used by the application that has to prove it renders whatever a port says.
///
/// Nothing here is a stub that returns a plausible default. Every member either
/// answers from what the test gave it or throws, because a fake that quietly
/// returns an empty list is the exact failure ADR-0009's contract was written
/// against.
library;

export 'src/testing/fake_native.dart';
