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

/// The strip along the top of the panel that moves it.
///
/// A borderless panel has no title bar to grab, and a Flutter view inside the
/// window cannot move the window it is drawn in. So the handle is a real view,
/// above the Flutter content: the header the panel draws is the handle's twin, and
/// the two must stay the same height.
final class PanelDragStrip: NSView {
    /// Called once, when the drag ends: the window's rectangle and the screen's,
    /// both in the top-left-origin space the contract uses.
    var onDragEnded: ((CGRect, CGRect) -> Void)?

    private var startLocation: NSPoint = .zero
    private var startOrigin: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        startLocation = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: startOrigin.x + (now.x - startLocation.x),
            y: startOrigin.y + (now.y - startLocation.y)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window, let screen = PanelDragStrip.screenRect(for: window) else { return }
        onDragEnded?(PanelDragStrip.quartz(window.frame), screen)
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

/// The window itself: an `NSPanel` running its own Flutter engine.
///
/// **A second engine, deliberately.** ADR-0012 gives the panel its own window so
/// it can float above the chat and outlive the main window being closed. On
/// desktop that means a second engine and a second isolate, and the only thing
/// that crosses between them is the panel protocol in the application.
final class FloatingPanelHost: NSObject {
    static let shared = FloatingPanelHost()

    /// Where the panel's Flutter code starts. The application provides it; the
    /// plugin does not know what is drawn in there.
    static let entrypoint = "panelMain"

    /// The strip's height, in points. The panel's own header is a handle of the
    /// same height and the two are drawn on top of each other.
    static let dragStripHeight: CGFloat = 28

    private static let defaultSize = NSSize(width: 420, height: 620)

    /// Set by the plugin; every panel event goes out through here.
    var onEvent: (([String: Any]) -> Void)?

    private var panel: MiaotouPanel?
    private var engine: FlutterEngine?
    private var lastPlacement: CGRect?

    /// This application's own windows, for the capture to leave out.
    var ownWindowIds: [CGWindowID] {
        guard let panel, panel.isVisible else { return [] }
        return [CGWindowID(panel.windowNumber)]
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
        let screen = panel.flatMap { PanelDragStrip.screenRect(for: $0) }
            ?? NSScreen.main.map { PanelDragStrip.quartz($0.visibleFrame) }
            ?? .zero
        let window = panel.map { PanelDragStrip.quartz($0.frame) } ?? .zero
        return ["screen": PanelDragHost.dictionary(screen), "window": PanelDragHost.dictionary(window)]
    }

    // MARK: - Showing and hiding

    /// Shows the panel, or moves it if it is already up.
    ///
    /// [at] wins over [anchor]: a position computed in Dart — a snapped edge, or
    /// the place the panel was left — is more specific than a corner, and the two
    /// are never both given.
    func show(anchor: String, dx: Double, dy: Double, at: CGRect?) {
        let panel = ensurePanel()
        let screen = PanelDragStrip.screenRect(for: panel) ?? .zero
        let target = at ?? FloatingPanelHost.anchorRect(
            anchor: anchor,
            screen: screen,
            size: panel.frame.size,
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

    /// Takes the panel off screen. Returns whether it was on screen, so the caller
    /// can restore exactly what it took and not invent a window the user closed.
    @discardableResult
    func hide() -> Bool {
        guard let panel, panel.isVisible else { return false }
        lastPlacement = PanelDragStrip.quartz(panel.frame)
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

        let panel = MiaotouPanel(
            contentRect: NSRect(origin: .zero, size: FloatingPanelHost.defaultSize),
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

        let strip = PanelDragStrip(frame: NSRect(
            x: 0,
            y: panel.frame.height - FloatingPanelHost.dragStripHeight,
            width: panel.frame.width,
            height: FloatingPanelHost.dragStripHeight
        ))
        strip.autoresizingMask = [.width, .minYMargin]
        strip.onDragEnded = { [weak self] window, screen in
            self?.onEvent?(["kind": "dragged", "window": PanelDragHost.dictionary(window), "screen": PanelDragHost.dictionary(screen)])
        }
        panel.contentView?.addSubview(strip, positioned: .above, relativeTo: nil)

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

/// Turns a rectangle into the map the channel carries.
enum PanelDragHost {
    static func dictionary(_ rect: CGRect) -> [String: Any] {
        [
            "left": Double(rect.minX),
            "top": Double(rect.minY),
            "right": Double(rect.maxX),
            "bottom": Double(rect.maxY),
        ]
    }
}
