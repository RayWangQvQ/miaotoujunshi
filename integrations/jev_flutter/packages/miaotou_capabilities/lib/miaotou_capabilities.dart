/// The ten capability interfaces, and nothing that talks to a platform.
///
/// ADR-0009 makes this package the only boundary between the platform
/// implementations and everything above them. Two properties follow from that
/// and are worth knowing before editing anything here:
///
/// * **It is platform-free.** It imports no Flutter library and no `dart:io`, so
///   every package that depends on it can be exercised with `dart test` — which
///   is what makes the domain layer testable without a device at all.
/// * **Every member must be answerable.** A port either implements a member or
///   refuses it out loud; see `support.dart` for the two refusals and why they
///   are distinct.
library;

export 'src/capability_set.dart';
export 'src/material/shared_payload.dart';
export 'src/member_manifest.dart';
export 'src/model/chat_snapshot.dart';
export 'src/model/conversation_ref.dart';
export 'src/model/screen_rect.dart';
export 'src/model/speaker.dart';
export 'src/platform/floating_panel.dart';
export 'src/platform/ocr.dart';
export 'src/platform/screen_capture.dart';
export 'src/platform/text_inject.dart';
export 'src/platform/ui_tree_reader.dart';
export 'src/storage/knowledge_store.dart';
export 'src/storage/memory_store.dart';
export 'src/storage/preferences.dart';
export 'src/storage/secret_store.dart';
export 'src/support.dart';
