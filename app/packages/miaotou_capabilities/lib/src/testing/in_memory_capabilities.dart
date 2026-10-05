import 'dart:async';
import 'dart:typed_data';

import '../capability_set.dart';
import '../material/shared_payload.dart';
import '../model/chat_snapshot.dart';
import '../model/conversation_ref.dart';
import '../model/screen_rect.dart';
import '../model/speaker.dart';
import '../platform/floating_panel.dart';
import '../platform/ocr.dart';
import '../platform/screen_capture.dart';
import '../platform/text_inject.dart';
import '../platform/ui_tree_reader.dart';
import '../storage/knowledge_store.dart';
import '../storage/memory_store.dart';
import '../storage/preferences.dart';
import '../storage/secret_store.dart';

/// A complete implementation of the ten capabilities that touches nothing.
///
/// It exists for two reasons. ADR-0009 makes `miaotou_domain` platform-free, and
/// a platform-free package cannot be tested at all without a platform-free
/// implementation of the contract. And the seam is only real if something other
/// than a platform can be plugged into it: this is what lets the whole
/// application be driven end to end with no device in the loop.
///
/// It lives in the interface package rather than in a platform package so that
/// all three platform packages, the domain and the application can share one —
/// the same reasoning behind `package:http/testing.dart`.
///
/// Every member answers. A double is the reference for what "a member that
/// works" looks like, so a refusal here would be a defect in the double rather
/// than a statement about a platform.
final class InMemoryCapabilities {
  InMemoryCapabilities({
    String? targetWindow,
    CaptureOutcome? captureOutcome,
    Object? captureThrows,
    List<OcrLine>? ocrLines,
    bool verifyInjection = true,
    List<ChatLine>? chatLines,
    Map<String, List<int>>? files,
    Map<String, Object>? preferences,
    Map<String, String>? secrets,
    List<KnowledgeNote>? notes,
    List<KnowledgeContact>? contacts,
    MemoryStatus? memoryStatus,
  })  : screenCapture = InMemoryScreenCapture(
          targetWindow: targetWindow,
          outcome: captureOutcome,
          captureThrows: captureThrows,
        ),
        uiTreeReader = InMemoryUiTreeReader(lines: chatLines),
        ocr = InMemoryOcr(lines: ocrLines),
        textInject = InMemoryTextInject(verify: verifyInjection),
        floatingPanel = InMemoryFloatingPanel(),
        payload = InMemorySharedPayload(files: files),
        preferences = InMemoryPreferences(values: preferences),
        secretStore = InMemorySecretStore(secrets: secrets),
        knowledgeStore = InMemoryKnowledgeStore(notes: notes, contacts: contacts),
        memoryStore = InMemoryMemoryStore(memoryStatus: memoryStatus);

  final InMemoryScreenCapture screenCapture;
  final InMemoryUiTreeReader uiTreeReader;
  final InMemoryOcr ocr;
  final InMemoryTextInject textInject;
  final InMemoryFloatingPanel floatingPanel;
  final InMemorySharedPayload payload;
  final InMemoryPreferences preferences;
  final InMemorySecretStore secretStore;
  final InMemoryKnowledgeStore knowledgeStore;
  final InMemoryMemoryStore memoryStore;

  /// The ten as a [CapabilitySet], ready to hand to the application.
  CapabilitySet toSet() => CapabilitySet(
        screenCapture: screenCapture,
        uiTreeReader: uiTreeReader,
        ocr: ocr,
        textInject: textInject,
        floatingPanel: floatingPanel,
        sharedPayload: payload,
        preferences: preferences,
        secretStore: secretStore,
        knowledgeStore: knowledgeStore,
        memoryStore: memoryStore,
      );

  /// Closes the two streams the double owns. A widget test that leaves a
  /// broadcast controller open fails on a pending timer, so this is not
  /// optional.
  void dispose() {
    uiTreeReader.dispose();
    floatingPanel.dispose();
  }
}

/// A small opaque frame, so a capture answers with pixels rather than nothing.
CaptureFrame _defaultFrame() => CaptureFrame(
      pixels: Uint8List.fromList(List<int>.filled(2 * 2 * 4, 0xff)),
      width: 2,
      height: 2,
      scaleX: 1,
      scaleY: 1,
      originX: 0,
      originY: 0,
    );

final class InMemoryScreenCapture implements ScreenCapture {
  InMemoryScreenCapture({
    this.targetWindow,
    CaptureOutcome? outcome,
    this.captureThrows,
  }) : outcome = outcome ?? CaptureOk(_defaultFrame());

  /// What [findTargetWindow] answers. Null is the "no window found" case and is
  /// the default, because it is the one a real port hits most often.
  String? targetWindow;

  /// What [capture] answers.
  CaptureOutcome outcome;

  /// What [capture] throws instead of answering.
  ///
  /// The contract gives a refusal a value and an exception to a platform that
  /// cannot answer at all, so this is not a refusal this double is pretending
  /// to make — it is the other half of the interface, and the Android bridge
  /// reaches it the moment its accessibility service is off.
  Object? captureThrows;

  /// Every `targetWindowId` [capture] was called with, in order.
  final List<String?> captureCalls = <String?>[];

  @override
  Future<String?> findTargetWindow() async => targetWindow;

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    captureCalls.add(targetWindowId);
    final Object? failure = captureThrows;
    if (failure != null) {
      throw failure;
    }
    return outcome;
  }
}

final class InMemoryUiTreeReader implements UiTreeReader {
  InMemoryUiTreeReader({List<ChatLine>? lines})
      : lines = lines ??
            <ChatLine>[
              const ChatLine(speaker: Speaker.other, text: '在吗'),
            ];

  final List<ChatLine> lines;
  ChatUiSnapshot? _current;

  final StreamController<ChatUiSnapshot> _snapshots =
      StreamController<ChatUiSnapshot>.broadcast();

  @override
  Future<ChatUiSnapshot?> readActiveChat() async =>
      _current ??
      ChatUiSnapshot(
        conversation: const ConversationRef(
          packageName: 'com.tencent.mm',
          title: '张三',
        ),
        lines: lines,
        capturedAt: DateTime.now(),
      );

  @override
  Stream<ChatUiSnapshot> get snapshots => _snapshots.stream;

  /// Pushes one snapshot down the stream, the way Android's accessibility
  /// service does.
  void push(ChatUiSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  void dispose() => _snapshots.close();
}

final class InMemoryOcr implements Ocr {
  InMemoryOcr({List<OcrLine>? lines})
      : lines = lines ??
            <OcrLine>[
              const OcrLine(
                text: '在吗',
                bounds: ScreenRect.fromLTWH(0, 0, 40, 20),
                confidence: 1,
              ),
            ];

  final List<OcrLine> lines;

  /// The language list of every call. Recorded so a test can assert that the
  /// caller chose it rather than the implementation.
  final List<List<String>> languageCalls = <List<String>>[];

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    languageCalls.add(List<String>.of(languages));
    return lines;
  }
}

final class InMemoryTextInject implements TextInject {
  InMemoryTextInject({this.verify = true});

  /// Whether injections report a verified landing. Set false to exercise the
  /// path where the text did not arrive.
  bool verify;

  /// Every text injected, in order.
  final List<String> injected = <String>[];

  /// Every window an injection was aimed at, in order.
  final List<String> targets = <String>[];

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async {
    injected.add(text);
    targets.add(target.windowId);
    return verify
        ? InjectResult.verified(text)
        : const InjectResult.unverified('the double was told not to verify');
  }
}

final class InMemoryFloatingPanel implements FloatingPanel {
  /// Every call in order, named as it was made.
  final List<String> calls = <String>[];

  final List<PanelPlacement> placements = <PanelPlacement>[];
  final List<bool> focusable = <bool>[];

  final StreamController<PanelEvent> _events =
      StreamController<PanelEvent>.broadcast();

  bool visible = false;

  @override
  Future<void> show({required PanelPlacement placement}) async {
    calls.add('show');
    placements.add(placement);
    visible = true;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    visible = false;
  }

  @override
  Future<void> hideForCapture() async => calls.add('hideForCapture');

  @override
  Future<void> restoreAfterCapture() async => calls.add('restoreAfterCapture');

  @override
  Future<void> setFocusable(bool value) async {
    calls.add('setFocusable($value)');
    focusable.add(value);
  }

  @override
  Stream<PanelEvent> get events => _events.stream;

  /// Emits one event, the way a port would when the user drags or taps.
  void emit(PanelEvent event) => _events.add(event);

  void dispose() => _events.close();
}

final class InMemorySharedPayload implements SharedPayload {
  InMemorySharedPayload({Map<String, List<int>>? files})
      : files = <String, Uint8List>{
          for (final MapEntry<String, List<int>> entry
              in (files ?? const <String, List<int>>{}).entries)
            entry.key: Uint8List.fromList(entry.value),
        };

  /// Keyed by repository-root-relative path, the same convention the payload
  /// map uses.
  final Map<String, Uint8List> files;

  /// Every key read, in order — the list a packaging guard compares against the
  /// built artifact.
  final List<String> reads = <String>[];

  @override
  Future<Uint8List> read(String repoRelativePath) async {
    reads.add(repoRelativePath);
    final Uint8List? bytes = files[repoRelativePath];
    if (bytes == null) {
      throw StateError('no payload file at $repoRelativePath');
    }
    return bytes;
  }

  @override
  Future<List<String>> list(String repoRelativeDir) async {
    final String prefix =
        repoRelativeDir.endsWith('/') ? repoRelativeDir : '$repoRelativeDir/';
    return files.keys
        .where((String key) => key.startsWith(prefix))
        .map((String key) => key.substring(prefix.length))
        .where((String rest) => rest.isNotEmpty && !rest.contains('/'))
        .toList()
      ..sort();
  }
}

final class InMemoryPreferences implements Preferences {
  InMemoryPreferences({Map<String, Object>? values})
      : values = <String, Object>{...?values};

  final Map<String, Object> values;

  T? _typed<T>(String key) {
    final Object? value = values[key];
    if (value == null) {
      return null;
    }
    if (value is T) {
      return value as T;
    }
    throw StateError('preference $key holds ${value.runtimeType}, not $T');
  }

  @override
  Future<String?> getString(String key) async => _typed<String>(key);

  @override
  Future<bool?> getBool(String key) async => _typed<bool>(key);

  @override
  Future<int?> getInt(String key) async => _typed<int>(key);

  @override
  Future<List<String>?> getStringList(String key) async =>
      _typed<List<String>>(key)?.toList();

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      values[key] = value.toList();

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

final class InMemorySecretStore implements SecretStore {
  InMemorySecretStore({Map<String, String>? secrets})
      : secrets = <String, String>{...?secrets};

  final Map<String, String> secrets;

  @override
  Future<String?> read(String key) async => secrets[key];

  @override
  Future<void> write(String key, String value) async => secrets[key] = value;

  @override
  Future<void> delete(String key) async => secrets.remove(key);

  @override
  Future<Set<String>> keys() async => secrets.keys.toSet();
}

final class InMemoryKnowledgeStore implements KnowledgeStore {
  InMemoryKnowledgeStore({
    List<KnowledgeNote>? notes,
    List<KnowledgeContact>? contacts,
  })  : noteList = <KnowledgeNote>[...?notes],
        contactList = <KnowledgeContact>[...?contacts];

  final List<KnowledgeNote> noteList;
  final List<KnowledgeContact> contactList;

  final Map<String, List<KnowledgeLogEntry>> logs =
      <String, List<KnowledgeLogEntry>>{};

  @override
  Future<List<KnowledgeNote>> notes() async => List<KnowledgeNote>.of(noteList);

  @override
  Future<void> saveNote(KnowledgeNote note) async {
    noteList
      ..removeWhere((KnowledgeNote other) => other.id == note.id)
      ..add(note);
  }

  @override
  Future<void> deleteNote(String id) async =>
      noteList.removeWhere((KnowledgeNote note) => note.id == id);

  @override
  Future<List<KnowledgeContact>> contacts() async =>
      List<KnowledgeContact>.of(contactList);

  @override
  Future<KnowledgeContact?> findContact({
    required String title,
    required String packageName,
  }) async {
    for (final KnowledgeContact contact in contactList) {
      final bool titleMatches =
          contact.name == title || contact.aliases.contains(title);
      if (!titleMatches) {
        continue;
      }
      if (contact.packageNames.isEmpty ||
          contact.packageNames.contains(packageName)) {
        return contact;
      }
    }
    return null;
  }

  @override
  Future<void> saveContact(KnowledgeContact contact) async {
    contactList
      ..removeWhere((KnowledgeContact other) => other.id == contact.id)
      ..add(contact);
  }

  @override
  Future<void> deleteContact(String id) async {
    contactList.removeWhere((KnowledgeContact contact) => contact.id == id);
    logs.remove(id);
  }

  @override
  Future<void> appendLog(String contactId, List<KnowledgeLogEntry> entries) async {
    logs.putIfAbsent(contactId, () => <KnowledgeLogEntry>[]).addAll(entries);
  }

  @override
  Future<List<KnowledgeLogEntry>> recentLog(
    String contactId, {
    required int limit,
  }) async {
    final List<KnowledgeLogEntry> all =
        logs[contactId] ?? const <KnowledgeLogEntry>[];
    return all.length <= limit
        ? List<KnowledgeLogEntry>.of(all)
        : all.sublist(all.length - limit);
  }

  @override
  Future<void> clearAll() async {
    noteList.clear();
    contactList.clear();
    logs.clear();
  }
}

final class InMemoryMemoryStore implements MemoryStore {
  InMemoryMemoryStore({MemoryStatus? memoryStatus})
      : memoryStatus = memoryStatus ??
            const MemoryStatus(
              consentEnabled: true,
              paused: false,
              atCapacity: false,
            );

  MemoryStatus memoryStatus;

  final Map<String, Map<String, String>> profiles =
      <String, Map<String, String>>{};

  /// One entry per successful write, oldest first, holding the value the field
  /// had before it — which is what [undo] puts back.
  final List<({String subjectId, String field, String? previous})> undoStack =
      <({String subjectId, String field, String? previous})>[];

  @override
  Future<MemoryStatus> status() async => memoryStatus;

  @override
  Future<List<MemoryRecord>> show(String subjectId) async =>
      (profiles[subjectId] ?? const <String, String>{})
          .entries
          .map((MapEntry<String, String> entry) => MemoryRecord(
                subjectId: subjectId,
                field: entry.key,
                value: entry.value,
              ))
          .toList();

  @override
  Future<void> apply({
    required String subjectId,
    required String field,
    required String value,
  }) async {
    if (!memoryStatus.acceptsWrites) {
      throw StateError('the memory store does not accept writes: $memoryStatus');
    }
    final Map<String, String> profile =
        profiles.putIfAbsent(subjectId, () => <String, String>{});
    undoStack
        .add((subjectId: subjectId, field: field, previous: profile[field]));
    profile[field] = value;
  }

  @override
  Future<int> undo() async {
    final int count = undoStack.length;
    for (final ({String subjectId, String field, String? previous}) entry
        in undoStack.reversed) {
      final Map<String, String> profile = profiles[entry.subjectId]!;
      final String? previous = entry.previous;
      if (previous == null) {
        profile.remove(entry.field);
      } else {
        profile[entry.field] = previous;
      }
    }
    undoStack.clear();
    return count;
  }
}
