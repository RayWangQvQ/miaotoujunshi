import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities_macos/miaotou_capabilities_macos.dart';

/// A scripted macOS.
///
/// The point of the seam ([MacosNative]) is that everything above it can be
/// exercised with no Mac attached. This is the Mac: it answers, it records the
/// order it was asked in, and it can be told to fail.
///
/// The call log is the interesting part. Several of the properties #14 asks for
/// are statements about **order** — the panel has to be hidden before the frame
/// is taken and given back after — and an assertion about the return value alone
/// cannot see an ordering mistake. #15 added a second use for it: the storage
/// members are asked *where* things are, and a test that did not control the
/// answer would be reading the developer's own container.
///
/// ## The two directories
///
/// [resourceRoot] and [containerDirectory] default to throw, so a test has to say
/// where the payload and the stores are. That is the point: a fake that invented
/// a path would let a test pass against a location nothing else uses. Pass
/// [resourceRoot] for a payload read and [containerDirectory] for a store; a
/// temporary directory each is the usual answer, and
/// [withTemporaryStorage] makes that a one-liner.
///
/// ## The keychain is a map
///
/// Held in memory and never on disk, which is what makes it safe for a fake to
/// hold a value at all. [keychainKeys] returns its keys and — like the real one —
/// there is deliberately no member anywhere that returns the values *as a list*,
/// so "which providers are configured" cannot be answered with the keys in hand.
class FakeMacosNative implements MacosNative {
  FakeMacosNative({
    this.windowId = '77',
    this.frame,
    this.lines = const <OcrLine>[],
    this.captureOutcome,
    this.injectResult,
    this.screen = const ScreenRect(left: 0, top: 0, right: 1440, bottom: 900),
    this.window = const ScreenRect(left: 100, top: 100, right: 520, bottom: 720),
    this.payloadRoot,
    this.containerRoot,
    Map<String, String>? keychain,
  }) : _keychain = keychain ?? <String, String>{};

  final String? windowId;
  final CaptureFrame? frame;
  final List<OcrLine> lines;

  /// What the next capture answers. Settable so a test can make one fail.
  CaptureOutcome? captureOutcome;

  /// What the next injection answers.
  InjectResult? injectResult;
  final ScreenRect screen;
  final ScreenRect window;

  /// Where the payload tree is, or null to refuse the question.
  ///
  /// Named `payloadRoot` rather than `resourceRoot` because the seam's member is
  /// a *method* of that name and a class cannot have both. Null rather than a
  /// default because a wrong default is worse than no answer: a test that forgot
  /// to say where the payload is would read whatever happened to be on the
  /// machine.
  ///
  /// Settable rather than final because one test needs to hand a store a root
  /// that has stopped working — a bundle that was never laid out, say — and
  /// building a second fake for it would say nothing about the first one.
  String? payloadRoot;

  /// Where the container stores live, or null to refuse the question.
  String? containerRoot;

  final Map<String, String> _keychain;

  /// Every call, in the order it arrived. `'hide'`, `'capture:77'`, `'show'`, …
  final List<String> log = <String>[];

  /// Whether the panel is on screen, which the real host tracks and this one has
  /// to as well: the restore path depends on knowing what was taken.
  bool panelUp = false;

  bool focusable = false;
  String? injectedText;

  final StreamController<NativePanelEvent> _events =
      StreamController<NativePanelEvent>.broadcast();

  /// Something the panel "said".
  void emit(NativePanelEvent event) => _events.add(event);

  @override
  Future<String?> findTargetWindow() async {
    log.add('findTargetWindow');
    return windowId;
  }

  @override
  Future<CaptureOutcome> capture({String? targetWindowId}) async {
    log.add('capture:$targetWindowId');
    return captureOutcome ??
        CaptureOk(
          frame ??
              CaptureFrame(
                pixels: Uint8List.fromList(<int>[1, 2, 3, 4]),
                width: 2,
                height: 1,
                scaleX: 1,
                scaleY: 1,
                originX: 0,
                originY: 0,
              ),
        );
  }

  @override
  Future<List<OcrLine>> recognize(
    CaptureFrame frame, {
    required List<String> languages,
  }) async {
    log.add('recognize:${languages.join('+')}');
    return lines;
  }

  @override
  Future<InjectResult> inject(String text, {required InjectTarget target}) async {
    log.add('inject:${target.windowId}');
    injectedText = text;
    return injectResult ?? InjectResult.verified(text);
  }

  @override
  Future<PanelGeometry> panelGeometry() async {
    log.add('panelGeometry');
    return PanelGeometry(screen: screen, window: window);
  }

  @override
  Future<void> showPanel({required PanelPlacement placement, ScreenRect? at}) async {
    log.add(at == null ? 'show:${placement.anchor.name}' : 'show:at');
    panelUp = true;
  }

  @override
  Future<void> restorePanel() async {
    log.add('restore');
    panelUp = true;
  }

  @override
  Future<bool> hidePanel() async {
    log.add('hide');
    final bool was = panelUp;
    panelUp = false;
    return was;
  }

  @override
  Future<void> setPanelFocusable(bool value) async {
    log.add('focusable:$value');
    focusable = value;
  }

  @override
  Stream<NativePanelEvent> get events => _events.stream;

  // -- #15: the storage half ------------------------------------------------
  //
  // Each of these logs under a name that says which question was asked, so a test
  // can assert that a store asked the *container* and not the *resource root* —
  // a payload directory and a writable directory are different places, and
  // swapping them writes user data into a read-only app bundle.

  @override
  Future<String> resourceRoot() async {
    log.add('resourceRoot');
    final String? root = payloadRoot;
    if (root == null) {
      throw StateError(
        'this fake was not told where the payload is; pass payloadRoot: so the '
            'test reads a directory it chose',
      );
    }
    return root;
  }

  @override
  Future<String> containerDirectory() async {
    log.add('containerDirectory');
    final String? directory = containerRoot;
    if (directory == null) {
      throw StateError(
        'this fake was not told where the container is; pass containerRoot: so '
            'the test writes to a temporary directory',
      );
    }
    return directory;
  }

  @override
  Future<String?> keychainRead(String key) async {
    log.add('keychain.read:$key');
    return _keychain[key];
  }

  @override
  Future<void> keychainWrite(String key, String value) async {
    log.add('keychain.write:$key');
    _keychain[key] = value;
  }

  @override
  Future<void> keychainDelete(String key) async {
    log.add('keychain.delete:$key');
    _keychain.remove(key);
  }

  @override
  Future<List<String>> keychainKeys() async {
    log.add('keychain.keys');
    return _keychain.keys.toList()..sort();
  }

  /// The keychain's contents, for a test that has to look at what was stored.
  ///
  /// Exposed on the fake and nowhere else. The real store has no such member —
  /// that is the whole of `keys()`'s contract — and a test needs it precisely
  /// because the production API will not offer it.
  Map<String, String> get keychainContents => Map<String, String>.unmodifiable(_keychain);

  Future<void> close() => _events.close();
}

/// A [FakeMacosNative] with a throwaway payload root and container directory.
///
/// The two are separate directories on purpose even though a test usually wants
/// both: the payload is copied into the bundle by the build and is read-only
/// there, while the container is the one place this app may write, and a fake
/// that pointed both at one directory would hide any confusion between them.
///
/// The caller deletes them with [deleteTemporaryStorage] in its own tear-down,
/// because a helper that registered the tear-down itself would fire it before a
/// test that wanted to read a file off disk had looked.
///
/// When [withPayload] is set, the payload directory starts as a copy of the
/// repository's real two trees — found by walking up, the way
/// `shared_payload_invariant_test.dart` does in the interface package. That is
/// what makes `macosCapabilities(native: fakeMacosWithTemporaryStorage())` able to
/// answer `sharedPayload.read` at all: a member that returns bytes must be able
/// to return *bytes*, and a `FileSystemException` from an empty directory would
/// be the right answer to the wrong question. A test that wants a specific
/// payload points the fake at its own directory instead.
FakeMacosNative fakeMacosWithTemporaryStorage({
  Map<String, String>? keychain,
  bool withPayload = false,
}) {
  final Directory payload =
      Directory.systemTemp.createTempSync('miaotou-payload-fake');
  final Directory container =
      Directory.systemTemp.createTempSync('miaotou-container-fake');
  if (withPayload) {
    _copyPayloadTrees(findRepositoryRoot(), payload);
  }
  return FakeMacosNative(
    payloadRoot: payload.path,
    containerRoot: container.path,
    keychain: keychain,
  );
}

/// The repository root, found by walking up until both payload trees are there.
///
/// The same definition `miaotou_capabilities`' own payload tests use. It is here
/// rather than imported because that one is under that package's `test/`, and a
/// shipping library cannot reach a sibling's test directory.
Directory findRepositoryRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    if (Directory('${directory.path}/goutoujunshi').existsSync() &&
        Directory('${directory.path}/miaotoujunshi').existsSync()) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'no repository root above ${Directory.current.absolute.path}',
      );
    }
    directory = parent;
  }
}

void _copyPayloadTrees(Directory repository, Directory into) {
  for (final String tree in <String>['miaotoujunshi', 'goutoujunshi']) {
    final Directory source = Directory('${repository.path}/$tree');
    if (!source.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity
        in source.listSync(recursive: true, followLinks: false)) {
      final String relative = entity.path.substring(repository.path.length + 1);
      final String target = '${into.path}/$relative';
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File) {
        Directory(File(target).parent.path).createSync(recursive: true);
        entity.copySync(target);
      }
    }
  }
}

/// Deletes [native]'s two temporary directories.
///
/// Split out from [fakeMacosWithTemporaryStorage] so the paths are reachable: a
/// test that wants to read a store's file has to know where the file is, and a
/// helper that hid the directory would make "the file is really there" something
/// only a white-box assertion could say.
void deleteTemporaryStorage(FakeMacosNative native) {
  for (final String? path in <String?>[native.payloadRoot, native.containerRoot]) {
    if (path != null) {
      final Directory directory = Directory(path);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  }
}
