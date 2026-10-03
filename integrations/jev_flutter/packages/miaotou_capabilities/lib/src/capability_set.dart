import 'material/shared_payload.dart';
import 'platform/floating_panel.dart';
import 'platform/ocr.dart';
import 'platform/screen_capture.dart';
import 'platform/text_inject.dart';
import 'platform/ui_tree_reader.dart';
import 'storage/knowledge_store.dart';
import 'storage/memory_store.dart';
import 'storage/preferences.dart';
import 'storage/secret_store.dart';

/// The ten capabilities a port answers for, in the four groups ADR-0009 names.
///
/// The value of this type is the constructor: it takes all ten by name and has
/// no defaults, so a platform implementation package cannot compile while it is
/// missing one. That is the property the three-stack layout has no equivalent
/// for — a new capability cannot be added without all three ports answering for
/// it, because the compiler asks each of them.
///
/// It is deliberately a plain record and not an interface: the *interfaces* are
/// the ten above, and a fourth "capability set interface" would only be a place
/// for a platform to opt out of the rule.
final class CapabilitySet {
  const CapabilitySet({
    required this.screenCapture,
    required this.uiTreeReader,
    required this.ocr,
    required this.textInject,
    required this.floatingPanel,
    required this.sharedPayload,
    required this.preferences,
    required this.secretStore,
    required this.knowledgeStore,
    required this.memoryStore,
  });

  final ScreenCapture screenCapture;
  final UiTreeReader uiTreeReader;
  final Ocr ocr;
  final TextInject textInject;
  final FloatingPanel floatingPanel;

  final SharedPayload sharedPayload;

  final Preferences preferences;
  final SecretStore secretStore;
  final KnowledgeStore knowledgeStore;
  final MemoryStore memoryStore;

  /// One line per capability naming the implementation answering for it.
  ///
  /// It reads types, never calls anything, so a set whose members all refuse
  /// still produces a full report. That is what lets one screen show what a port
  /// supports without a device to try it on.
  Map<String, String> describe() => <String, String>{
        'screenCapture': screenCapture.runtimeType.toString(),
        'uiTreeReader': uiTreeReader.runtimeType.toString(),
        'ocr': ocr.runtimeType.toString(),
        'textInject': textInject.runtimeType.toString(),
        'floatingPanel': floatingPanel.runtimeType.toString(),
        'sharedPayload': sharedPayload.runtimeType.toString(),
        'preferences': preferences.runtimeType.toString(),
        'secretStore': secretStore.runtimeType.toString(),
        'knowledgeStore': knowledgeStore.runtimeType.toString(),
        'memoryStore': memoryStore.runtimeType.toString(),
      };

  @override
  String toString() => 'CapabilitySet(${describe().values.join(', ')})';
}
