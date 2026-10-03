/// The in-memory implementation of the ten capabilities, and the tool that keeps
/// what a member threw.
///
/// This library is the reason the seam can be tested at all: ADR-0009 makes
/// `miaotou_domain` platform-free, so nothing above the contract can be exercised
/// without a platform-free implementation of it. It lives in the interface package
/// so that the domain, the application and all three platform packages can share
/// one — the same reasoning behind `package:http/testing.dart`.
///
/// **Nothing in a release build imports this.** An application with a real
/// platform takes its capabilities from a platform package; the manifest of the
/// contract's members, which a support report does need, lives in the shipping
/// library instead.
library;

export 'src/testing/in_memory_capabilities.dart';
export 'src/testing/probe_capture.dart';
