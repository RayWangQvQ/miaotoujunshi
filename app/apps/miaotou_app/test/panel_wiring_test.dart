import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaotou_app/src/capability_registry.dart';
import 'package:miaotou_app/src/panel/protocol.dart';
import 'package:miaotou_app/src/panel/session.dart';
import 'package:miaotou_app/src/panel/window_channel.dart';
import 'package:miaotou_app/src/runtime/panel_settings.dart';
import 'package:miaotou_capabilities/miaotou_capabilities.dart';
import 'package:miaotou_capabilities/testing.dart';

/// What each port writes down once and every other end has to agree with.
///
/// Literal rather than read from the constants, for the reason
/// `panel_window_test.dart` gives about the macOS one: a name two processes have
/// to agree on is worth pinning from the side that does not own the other end. Two
/// of these are private in `window_channel.dart`, so a mock is the only way to
/// state them — and a mock that no longer matches fails loudly here rather than on
/// a device.
const String _androidBootstrap = 'miaotoujunshi/android/panel-bootstrap';
const String _androidProtocol = 'miaotoujunshi/android/panel-protocol';
const String _macosBootstrap = 'miaotoujunshi/macos/panel-bootstrap';
const String _macosProtocol = 'miaotoujunshi/macos/panel-protocol';
const String _windowsProtocol = 'miaotoujunshi/windows/panel-protocol';

/// The channel `desktop_multi_window` carries every window channel over.
///
/// The Windows port has no `MethodChannel` of its own: its window channel is a
/// name the plugin relays, so the only thing a test can stand in for is the
/// plugin's own host channel, with `registerMethodHandler` and the `invokeMethod`
/// that carries a frame to the other window.
const String _multiWindowHost = 'mixin.one/desktop_multi_window/channels';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// One mocked platform side, and everything this process sent it.
///
/// A mock rather than a seam in the implementation, which is the choice that makes
/// these tests worth having: the real `PanelEngineBootstrap` asks its host and
/// retries, the real view channel binds a handler and announces `panelReady`, and
/// the real main channel encodes both values. Nothing is replaced except the
/// process on the far side of the channel.
final class _Host {
  _Host(this.name, {this.answer});

  final String name;

  /// What the host replies to every call, or null for "nothing".
  final Future<Object?> Function(MethodCall call)? answer;

  final List<MethodCall> calls = <MethodCall>[];

  List<String> get methods => <String>[
    for (final MethodCall call in calls) call.method,
  ];

  static _Host install(
    String name, {
    Future<Object?> Function(MethodCall call)? answer,
  }) {
    final _Host host = _Host(name, answer: answer);
    _messenger.setMockMethodCallHandler(MethodChannel(name), (
      MethodCall call,
    ) async {
      host.calls.add(call);
      return host.answer == null ? null : host.answer!(call);
    });
    addTearDown(
      () => _messenger.setMockMethodCallHandler(MethodChannel(name), null),
    );
    return host;
  }

  /// The host calling back into this process, the way the panel sends a command.
  Future<void> send(String method, [Object? arguments]) => _messenger
      .handlePlatformMessage(
        name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (ByteData? _) {},
      );
}

/// Every channel a `startPanel` or an `attachPanelWindow` may talk to.
///
/// All of them are installed for every test rather than only the one under test: a
/// test that forgot one would fail with a missing plugin from inside the channel it
/// was not watching, which reads as a fault in the port rather than in the test.
final class _Hosts {
  _Hosts({required String androidRole, required String macosRole})
    : androidBootstrap = _Host.install(
        _androidBootstrap,
        answer: (MethodCall _) async => androidRole,
      ),
      androidProtocol = _Host.install(_androidProtocol),
      macosBootstrap = _Host.install(
        _macosBootstrap,
        answer: (MethodCall _) async => macosRole,
      ),
      macosProtocol = _Host.install(_macosProtocol),
      multiWindow = _Host.install(_multiWindowHost);

  final _Host androidBootstrap;
  final _Host androidProtocol;
  final _Host macosBootstrap;
  final _Host macosProtocol;
  final _Host multiWindow;
}

/// The main window's store and panel session, with the hosts beside them.
({InMemoryCapabilities capabilities, PanelSession panel}) _mainWindow() {
  final PanelSession panel = PanelSession();
  addTearDown(panel.dispose);
  return (capabilities: InMemoryCapabilities(), panel: panel);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the three wirings', () {
    test('each port hands out its own main channel', () {
      expect(
        wiringFor(Port.android).mainChannel(),
        isA<AndroidPanelMainChannel>(),
        reason: 'the wiring is the only place that knows which channel carries '
            'the protocol. A wrong pairing is a panel talking on another port\'s '
            'channel name, which fails on a device and nowhere earlier',
      );
      expect(wiringFor(Port.macos).mainChannel(), isA<MacosPanelMainChannel>());
      expect(
        wiringFor(Port.windows).mainChannel(),
        isA<WindowsPanelMainChannel>(),
      );
    });

    test('a wiring hands out a channel that has not been spoken to', () {
      final PanelWiring wiring = wiringFor(Port.android);

      expect(
        identical(wiring.mainChannel(), wiring.mainChannel()),
        isFalse,
        reason: 'initializing binds the channel\'s call handler, and a second '
            'show would silently take the first window\'s commands away from it',
      );
    });

    test(
      'the ball starts in a corner on Android and macOS and free on Windows',
      () {
        for (final Port port in <Port>[Port.android, Port.macos]) {
          expect(wiringFor(port).firstRun.anchor, PanelAnchor.topLeft);
          expect(wiringFor(port).firstRun.dx, 12);
          expect(wiringFor(port).firstRun.dy, 56);
        }

        expect(
          wiringFor(Port.windows).firstRun.anchor,
          PanelAnchor.free,
          reason: 'free is the anchor that means "the next show resolves where I '
              'was left": a desktop window is placed by its own saved placement '
              'rather than pinned to a corner of the screen',
        );
      },
    );
  });

  group('the panel engine asks which side it is', () {
    test('the main window is not a panel engine', () async {
      final _Hosts hosts = _Hosts(androidRole: 'main', macosRole: 'panel');

      expect(await attachPanelWindow(wiringFor(Port.android)), isNull);
      expect(hosts.androidBootstrap.methods, <String>['whichEngine']);
      expect(
        hosts.androidProtocol.calls,
        isEmpty,
        reason: 'the main window must not announce a panel it is not, and it must '
            'not ask its host to resume an engine that has no window',
      );
    });

    test('the panel engine gets its window and says it is up', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');

      final PanelWindowRuntime? runtime = await attachPanelWindow(
        wiringFor(Port.android),
      );

      expect(runtime, isNotNull);
      expect(runtime!.channel, isA<AndroidPanelViewChannel>());
      expect(
        hosts.androidBootstrap.methods,
        <String>['whichEngine', 'appResumed'],
        reason: 'Android only, and the whole reason `markResumed` is a parameter '
            'of the shared attach: an engine the host started without a window '
            'does not get its resume callback on its own, so the host has to be '
            'told. Losing this call leaves a panel that never resumes',
      );
      expect(
        hosts.androidProtocol.methods,
        <String>['panelReady'],
        reason: 'the main window has been holding the first frame since it showed '
            'this window; without panelReady both values are lost',
      );
    });

    test('macOS is not told the engine resumed', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');

      final PanelWindowRuntime? runtime = await attachPanelWindow(
        wiringFor(Port.macos),
      );

      expect(runtime, isNotNull);
      expect(
        hosts.macosBootstrap.methods,
        <String>['whichEngine'],
        reason: 'the macOS host does not implement appResumed: sending it would '
            'be a call the Swift side answers with a missing-plugin error, which '
            'is the failure this split exists to avoid',
      );
      expect(hosts.macosProtocol.methods, <String>['panelReady']);
    });

    test('the window calls reach that port\'s own channel', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');
      final PanelWindowRuntime runtime = (await attachPanelWindow(
        wiringFor(Port.android),
      ))!;

      await runtime.setExpanded(true);
      await runtime.startDragging();
      await runtime.setFocusable(false);

      expect(
        hosts.androidProtocol.methods,
        <String>['panelReady', 'setExpanded', 'startDragging', 'setFocusable'],
        reason: 'the runtime is handed the channel\'s own methods on the ports '
            'that own a window through the host. Wiring it to anything else would '
            'leave expand, drag and focus silently doing nothing',
      );
      expect(
        (hosts.androidProtocol.calls[1].arguments as Map<Object?, Object?>)['value'],
        true,
      );
      expect(
        (hosts.androidProtocol.calls[3].arguments as Map<Object?, Object?>)['value'],
        false,
      );
    });
  });

  group('the main window starts the panel', () {
    test('the ball lands on the port\'s own first-run corner', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');
      expect(hosts.multiWindow.name, _multiWindowHost);

      for (final Port port in Port.values) {
        final ({InMemoryCapabilities capabilities, PanelSession panel}) app =
            _mainWindow();

        await startPanel(wiringFor(port), app.capabilities.toSet(), app.panel);

        final PanelPlacement shown =
            app.capabilities.floatingPanel.placements.single;
        final PanelPlacement firstRun = wiringFor(port).firstRun;
        expect(shown.anchor, firstRun.anchor, reason: '$port');
        expect(shown.dx, firstRun.dx, reason: '$port');
        expect(shown.dy, firstRun.dy, reason: '$port');
        expect(
          shown.width,
          56,
          reason: 'the collapsed ball is the panel\'s initial size on every port: '
              'a saved placement says nothing about size, because size is not a '
              'setting',
        );
        expect(shown.height, 56, reason: '$port');
        expect(app.capabilities.floatingPanel.visible, isTrue, reason: '$port');
      }
    });

    test('a placement the user dragged wins over the first-run corner', () async {
      _Hosts(androidRole: 'panel', macosRole: 'panel');
      final ({InMemoryCapabilities capabilities, PanelSession panel}) app =
          _mainWindow();
      await PanelSettings.savePlacement(
        app.capabilities.preferences,
        const PanelPlacement(anchor: PanelAnchor.free, dx: 300, dy: 200),
      );

      await startPanel(wiringFor(Port.android), app.capabilities.toSet(), app.panel);

      final PanelPlacement shown =
          app.capabilities.floatingPanel.placements.single;
      expect(
        <Object?>[shown.anchor, shown.dx, shown.dy],
        <Object?>[PanelAnchor.free, 300, 200],
        reason: 'the corner is only a first run: a panel that ignored the '
            'placement the user dragged it to would jump back on every restart',
      );
    });

    test('both values go down, appearance first', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');
      final ({InMemoryCapabilities capabilities, PanelSession panel}) app =
          _mainWindow();

      await startPanel(wiringFor(Port.android), app.capabilities.toSet(), app.panel);

      expect(
        hosts.androidProtocol.methods,
        <String>['appearance', 'frame'],
        reason: 'the panel is painted before it has anything to say, and a frame '
            'that arrived first would be a window with no fill',
      );
    });

    test('a close from the panel hides the window', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');
      final ({InMemoryCapabilities capabilities, PanelSession panel}) app =
          _mainWindow();
      await startPanel(wiringFor(Port.android), app.capabilities.toSet(), app.panel);

      await hosts.androidProtocol.send(
        'command',
        PanelWireCodec.encodeCommand(const PanelCommand(PanelCommandKind.close)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        app.capabilities.floatingPanel.calls,
        contains('hide'),
        reason: 'close is the one command the main window acts on by itself; if '
            'the wiring drops the command stream the ball cannot be dismissed',
      );
    });

    test('Windows pushes both values down its window channel', () async {
      final _Hosts hosts = _Hosts(androidRole: 'panel', macosRole: 'panel');
      final ({InMemoryCapabilities capabilities, PanelSession panel}) app =
          _mainWindow();

      await startPanel(wiringFor(Port.windows), app.capabilities.toSet(), app.panel);

      final List<Map<Object?, Object?>> relays = <Map<Object?, Object?>>[
        for (final MethodCall call in hosts.multiWindow.calls)
          if (call.method == 'invokeMethod')
            (call.arguments as Map<Object?, Object?>),
      ];
      expect(
        <Object?>[
          for (final Map<Object?, Object?> relay in relays)
            <Object?>[relay['channel'], relay['method']],
        ],
        <Object?>[
          <Object?>[_windowsProtocol, 'appearance'],
          <Object?>[_windowsProtocol, 'frame'],
        ],
        reason: 'this is all a test can reach of the Windows port — the panel end '
            'of it asks the plugin for a real window and reshapes it — so what is '
            'pinned here is that the main window carries the protocol over the '
            'window channel and not over a MethodChannel no host is listening on',
      );
    });
  });
}
