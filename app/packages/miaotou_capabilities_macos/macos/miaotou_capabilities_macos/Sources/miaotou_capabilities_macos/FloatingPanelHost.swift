import Cocoa
import FlutterMacOS

/// The floating panel.
///
/// Every setting here was measured rather than read: gate experiment B established
/// on a real device that an `NSPanel` with `.nonactivatingPanel` at `.floating`
/// can be clicked and can host a Chinese input method while another application
/// stays the frontmost one, with the activation count at zero throughout.
///
/// Two of the comments below exist because the obvious alternative is wrong:
/// `hidesOnDeactivate` defaults to true and would make the panel vanish the
/// moment it works as intended, and becoming *main* is what brings an
/// application forward — key is fine, main is not.
final class MiaotouPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The window itself: an `NSPanel` running its own Flutter engine.
///
/// **A second engine, deliberately.** ADR-0012 gives the panel its own window so
/// it can float above the chat and outlive the main window being closed. On
/// desktop that means a second engine and a second isolate, and the only thing
/// that crosses between them is the panel protocol in the application.
///
/// **Both ends of that protocol live on this object**, because this is the one
/// thing holding the window they talk about. The main window's end is wired by
/// the plugin, which is the only place the main engine's messenger exists; the
/// panel's end is wired here, where the panel engine is created. macOS relays
/// through this object exactly as the Android host relays through Kotlin — the
/// alternative on Windows is `desktop_multi_window`, which pairs the two engines
/// directly and has no host in between.
final class FloatingPanelHost: NSObject {
    static let shared = FloatingPanelHost()

    /// Where the panel's Flutter code starts. The application provides it; the
    /// plugin does not know what is drawn in there.
    ///
    /// It resolves to `panelMain` in `lib/main.dart`, which is the application's
    /// own `main` again. The panel engine runs the same program as the main
    /// window and asks which side it is; on this port it asks over the bootstrap
    /// channel below.
    static let entrypoint = "panelMain"

    /// The two channel names, shared with the Dart side.
    ///
    /// `panel_window_test.dart` asserts both strings against the Dart, so a
    /// rename is a red test rather than a panel that silently stops receiving
    /// anything on a machine where nobody is watching.
    static let bootstrapChannelName = "miaotoujunshi/macos/panel-bootstrap"
    static let protocolChannelName = "miaotoujunshi/macos/panel-protocol"

    /// The two sizes the panel toggles between, in points.
    ///
    /// Stated here rather than on the Dart side because they are window sizes and
    /// nothing else on this port changes one. The collapsed panel is the ball and
    /// nothing else — a transparent 420x620 window with a 56pt ball in a corner
    /// still takes every click meant for the chat underneath it.
    static let collapsedSize = NSSize(width: 56, height: 56)
    static let expandedSize = NSSize(width: 420, height: 620)

    /// Set by the plugin; every panel event goes out through here.
    var onEvent: (([String: Any]) -> Void)?

    private var panel: MiaotouPanel?
    private var engine: FlutterEngine?
    private var lastPlacement: CGRect?

    /// The main window's end of the panel protocol, created by the plugin.
    private var mainProtocol: FlutterMethodChannel?

    /// The panel's end, created with the panel engine.
    private var panelProtocol: FlutterMethodChannel?

    /// Moves the window while the mouse button is held. See [beginDrag].
    private var dragTimer: Timer?

    /// This application's own windows, for the capture to leave out.
    var ownWindowIds: [CGWindowID] {
        guard let panel, panel.isVisible else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    // MARK: - The panel protocol

    /// Wires the **main window's** end of the panel protocol.
    ///
    /// Called once, from the plugin's `register`, because that is where the main
    /// engine's messenger is. Two channels rather than one because they answer
    /// two different questions — "which engine am I" and "carry this between the
    /// two" — and the bootstrap has to answer before anything else can be
    /// decided.
    func attachToMainEngine(messenger: FlutterBinaryMessenger) {
        let bootstrap = FlutterMethodChannel(
            name: FloatingPanelHost.bootstrapChannelName,
            binaryMessenger: messenger
        )
        bootstrap.setMethodCallHandler { call, result in
            if call.method == "whichEngine" {
                result("main")
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let protocolChannel = FlutterMethodChannel(
            name: FloatingPanelHost.protocolChannelName,
            binaryMessenger: messenger
        )
        protocolChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "frame", "appearance":
                // Down-stream only. The main window sends these; the panel engine
                // is the only thing that reads them, and it may not exist yet —
                // in which case the Dart side is holding the value and will send
                // it again when the panel reports that it is ready.
                self?.panelProtocol?.invokeMethod(call.method, arguments: call.arguments)
            default:
                result(FlutterMethodNotImplemented)
                return
            }
            result(nil)
        }
        mainProtocol = protocolChannel
    }

    // MARK: - Geometry

    /// Where the panel is, and how big the screen it is on is.
    func geometry() -> [String: Any] {
        // `panel` is optional — a host that has not built one yet has no window to
        // report — so the screen is asked of the panel only when there is one, and
        // the two fallbacks below stand in for it otherwise. Written with
        // `flatMap` for the same reason the next line uses `map`: passing the
        // optional straight into `screenRect(for:)` does not compile, because that
        // takes a non-optional `NSWindow`.
        let screen = panel.flatMap { PanelDragHost.screenRect(for: $0) }
            ?? NSScreen.main.map { PanelDragHost.quartz($0.visibleFrame) }
            ?? .zero
        let window = panel.map { PanelDragHost.quartz($0.frame) } ?? .zero
        return ["screen": PanelDragHost.dictionary(screen), "window": PanelDragHost.dictionary(window)]
    }

    // MARK: - Showing and hiding

    /// Shows the panel, or moves and resizes it if it is already up.
    ///
    /// [at] wins over [anchor]: a position computed in Dart — a snapped edge, or
    /// the place the panel was left — is more specific than a corner, and the two
    /// are never both given.
    ///
    /// [size] is what the caller wants the window to be, and it is stated on
    /// every show because the panel starts **collapsed**: this object's own
    /// default is the expanded window, so a caller that said nothing would get a
    /// transparent 420x620 rectangle over the chat.
    func show(anchor: String, dx: Double, dy: Double, size: CGSize?, at: CGRect?) {
        let panel = ensurePanel()
        let screen = PanelDragHost.screenRect(for: panel) ?? .zero
        let target = at ?? FloatingPanelHost.anchorRect(
            anchor: anchor,
            screen: screen,
            size: size ?? panel.frame.size,
            dx: dx,
            dy: dy
        )
        panel.setFrame(
            NSRect(
                x: FloatingPanelHost.appKitX(target.minX),
                y: FloatingPanelHost.appKitY(target.minY, height: target.height),
                width: target.width,
                height: target.height
            ),
            display: true
        )
        lastPlacement = target
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the panel must
        // come on screen without being activated, and asking for key here is what
        // would take the caret out of the chat.
        panel.orderFrontRegardless()
    }

    /// Resizes the panel when the user collapses or expands it.
    ///
    /// The collapsed panel is the ball and nothing else, and the size has to
    /// change for that to be true: on the other two ports the window is resized
    /// on the same toggle, and leaving it at 420x620 here would keep every click
    /// in that rectangle away from the chat underneath.
    ///
    /// Written in AppKit's own space, because that is the space the window is in
    /// — `visibleFrame` runs up from the bottom of the primary display, unlike
    /// the top-left space the panel protocol uses. Converting into the protocol's
    /// space and back would be two chances to get the sign wrong for no gain;
    /// [PanelDragHost] does that conversion at the one place it is unavoidable, in
    /// the events that leave this process.
    func setExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let size = expanded ? FloatingPanelHost.expandedSize : FloatingPanelHost.collapsedSize
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let current = panel.frame
        // Pinned to whichever vertical edge the window is nearer, which is the
        // rule `EdgeSnap` applies on the two desktop ports.
        let attachedRight = abs(current.maxX - visible.maxX) <= abs(current.minX - visible.minX)
        let x = attachedRight ? visible.maxX - size.width : visible.minX
        // AppKit's y runs up, so the panel's *top* edge is the one that stays put.
        let y = min(
            max(current.maxY - size.height, visible.minY),
            visible.maxY - size.height
        )
        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true
        )
        lastPlacement = PanelDragHost.quartz(panel.frame)
    }

    /// Moves the window with the mouse, for as long as the button is held.
    ///
    /// A timer rather than `performDrag(with:)`, which needs the mouse event
    /// itself: the panel engine's Dart is what decides that a drag began, and the
    /// event that caused it is delivered to the Flutter view rather than here.
    /// Polling the pointer is measured against the one coordinate space that
    /// matters — `NSEvent.mouseLocation` and a window's origin are both AppKit's,
    /// so the delta is a plain subtraction.
    ///
    /// The report at the end is the `dragged` event the application writes the
    /// placement from, which is also the event a snapped drag reports.
    func beginDrag() {
        guard let panel else { return }
        dragTimer?.invalidate()
        let startMouse = NSEvent.mouseLocation
        let startOrigin = panel.frame.origin
        dragTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] timer in
            guard let self, let panel = self.panel else {
                timer.invalidate()
                return
            }
            if NSEvent.pressedMouseButtons == 0 {
                timer.invalidate()
                self.dragTimer = nil
                self.reportDragEnded()
                return
            }
            let now = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(
                x: startOrigin.x + (now.x - startMouse.x),
                y: startOrigin.y + (now.y - startMouse.y)
            ))
        }
    }

    /// The window stopped moving. One event, whatever started the drag — and the
    /// only drag is the one the panel engine's Dart asked for.
    private func reportDragEnded() {
        guard let panel, let screen = PanelDragHost.screenRect(for: panel) else { return }
        let landed = PanelDragHost.quartz(panel.frame)
        lastPlacement = landed
        onEvent?([
            "kind": "dragged",
            "window": PanelDragHost.dictionary(landed),
            "screen": PanelDragHost.dictionary(screen),
        ])
    }

    /// Takes the panel off screen. Returns whether it was on screen, so the caller
    /// can restore exactly what it took and not invent a window the user closed.
    @discardableResult
    func hide() -> Bool {
        guard let panel, panel.isVisible else { return false }
        lastPlacement = PanelDragHost.quartz(panel.frame)
        panel.orderOut(nil)
        return true
    }

    /// Puts the panel back where it was.
    ///
    /// Deliberately not `show(anchor:topLeft)`: a panel the user has never dragged
    /// has no remembered position, and restoring it through an anchor would slide
    /// the window into the corner the first time a capture ended. The frame
    /// recorded when it was hidden is the only honest answer.
    func restore() {
        guard let panel else { return }
        if let place = lastPlacement {
            panel.setFrame(
                NSRect(
                    x: FloatingPanelHost.appKitX(place.minX),
                    y: FloatingPanelHost.appKitY(place.minY, height: place.height),
                    width: place.width,
                    height: place.height
                ),
                display: true
            )
        }
        panel.orderFrontRegardless()
    }

    /// Whether the panel may take keyboard focus.
    ///
    /// Not the style mask: a non-activating panel can hold key focus *and* host an
    /// input method, which is the property gate experiment B measured. What has to
    /// change is whether the panel grabs the caret unprompted — the collapsed ball
    /// must not, or typing continues in the chat with the caret somewhere else.
    func setFocusable(_ value: Bool) {
        panel?.becomesKeyOnlyIfNeeded = !value
    }

    /// Tells the panel its read-only state changed. The panel does not derive it
    /// (ADR-0002): the main window owns that decision and this only redraws.
    func reportReadOnly(_ readOnly: Bool) {
        onEvent?(["kind": "readOnly", "value": readOnly])
    }

    // MARK: - Construction

    private func ensurePanel() -> MiaotouPanel {
        if let panel {
            return panel
        }
        let engine = FlutterEngine(name: "miaotou-panel", project: nil)
        engine.run(withEntrypoint: FloatingPanelHost.entrypoint)
        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

        // The panel engine's end of both channels, created before its Dart runs.
        // The engine is started above and reaches Dart asynchronously, so a
        // handler registered here is always in place by the time the panel asks
        // which engine it is.
        let bootstrap = FlutterMethodChannel(
            name: FloatingPanelHost.bootstrapChannelName,
            binaryMessenger: engine.binaryMessenger
        )
        bootstrap.setMethodCallHandler { call, result in
            if call.method == "whichEngine" {
                result("panel")
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let protocolChannel = FlutterMethodChannel(
            name: FloatingPanelHost.protocolChannelName,
            binaryMessenger: engine.binaryMessenger
        )
        protocolChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(nil)
                return
            }
            let arguments = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "setExpanded":
                self.setExpanded(arguments["value"] as? Bool ?? false)
            case "startDragging":
                self.beginDrag()
            case "setFocusable":
                self.setFocusable(arguments["value"] as? Bool ?? false)
            case "command", "panelReady":
                // Up-stream, and both belong to the main window's Dart: the
                // commands reach the session, and `panelReady` is what releases
                // the frame and the appearance the main window has been holding
                // for a panel that was not listening yet.
                self.mainProtocol?.invokeMethod(call.method, arguments: call.arguments)
            default:
                result(FlutterMethodNotImplemented)
                return
            }
            result(nil)
        }
        panelProtocol = protocolChannel

        let panel = MiaotouPanel(
            contentRect: NSRect(origin: .zero, size: FloatingPanelHost.expandedSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The default is true, and it is the reason a translucent panel over a
        // dark chat window turns into an opaque rectangle on some hardware.
        panel.isMovableByWindowBackground = false

        self.panel = panel
        self.engine = engine
        return panel
    }

    // MARK: - Coordinates

    /// AppKit's y runs up from the bottom of the primary display; the contract's
    /// runs down from the top. Same primary, so the conversion is a subtraction
    /// and nothing else.
    static func appKitY(_ quartzTop: Double, height: Double) -> Double {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return primaryHeight - quartzTop - height
    }

    static func appKitX(_ quartzLeft: Double) -> Double {
        quartzLeft
    }

    static func anchorRect(
        anchor: String,
        screen: CGRect,
        size: CGSize,
        dx: Double,
        dy: Double
    ) -> CGRect {
        var origin: CGPoint
        switch anchor {
        case "topRight":
            origin = CGPoint(x: screen.maxX - size.width, y: screen.minY)
        case "bottomLeft":
            origin = CGPoint(x: screen.minX, y: screen.maxY - size.height)
        case "bottomRight":
            origin = CGPoint(x: screen.maxX - size.width, y: screen.maxY - size.height)
        case "free":
            origin = CGPoint(x: screen.minX + dx, y: screen.minY + dy)
        default:
            origin = CGPoint(x: screen.minX, y: screen.minY)
        }
        return CGRect(
            x: origin.x + (anchor == "free" ? 0 : dx),
            y: origin.y + (anchor == "free" ? 0 : dy),
            width: size.width,
            height: size.height
        )
    }
}

/// Turns a rectangle into the map the channel carries, and between the two
/// coordinate spaces the two sides speak.
///
/// **The drag handle used to be a real view here.** A borderless panel has no
/// title bar, and a Flutter view inside a window cannot move that window, so the
/// strip was an `NSView` drawn over the top of the panel's own header which moved
/// the window by hand. It is gone: the panel's Dart already asks for a drag on
/// every collapsed ball and on its header — the same code path Android and
/// Windows use — and a strip that stays 56pt wide when the panel collapses would
/// cover half the ball and take its taps.
enum PanelDragHost {
    static func dictionary(_ rect: CGRect) -> [String: Any] {
        [
            "left": Double(rect.minX),
            "top": Double(rect.minY),
            "right": Double(rect.maxX),
            "bottom": Double(rect.maxY),
        ]
    }

    /// The screen's visible area, in the space the contract uses.
    ///
    /// `visibleFrame` rather than `frame`: the menu bar and the Dock are not places
    /// a panel can be dragged to and left.
    static func screenRect(for window: NSWindow) -> CGRect? {
        let screen = window.screen ?? NSScreen.main
        guard let screen else { return nil }
        return quartz(screen.visibleFrame)
    }

    /// AppKit counts screen positions from the bottom left; the capture side counts
    /// them from the top left, because that is what the window server reports.
    ///
    /// Both spaces put the origin at the primary display, so the conversion is
    /// exact rather than approximate — which is the only reason it is done at all
    /// instead of the panel keeping a second frame in the other space.
    static func quartz(_ rect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
