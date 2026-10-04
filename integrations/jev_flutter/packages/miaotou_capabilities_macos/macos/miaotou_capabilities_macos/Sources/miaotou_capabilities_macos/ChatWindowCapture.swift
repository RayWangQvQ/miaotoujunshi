import CoreGraphics
import Foundation
import ScreenCaptureKit

/// One captured frame, in the shape the capability contract asks for.
///
/// The bytes are RGBA8 with the **first row at the top**, which is the order
/// every rectangle in this file is already in; a `CGBitmapContext` writes bottom-up
/// and is flipped on the way out so that nothing downstream has to know.
struct CapturedFrame {
    let pixels: Data
    let width: Int
    let height: Int

    /// Bitmap pixels per logical point, each axis. Not 1 by definition: a display
    /// capture lands at the display's own scale, and a window capture is taken at
    /// nominal 1x because Vision's cost scales with pixel count and chat text is
    /// still legible at 1x (measured: identical recognition, half the time).
    let scaleX: Double
    let scaleY: Double

    /// The window's top-left on screen, in logical points.
    let originX: Double
    let originY: Double
}

enum CaptureError: Error {
    case screenRecordingDenied
    case windowVanished
    case noImage(String)
}

/// Reading one application's window off the screen while something else is in
/// front of it.
///
/// ScreenCaptureKit is not a preference here, it is the mechanism: Quartz's
/// `CGWindowListCreateImage` was obsoleted in macOS 15, and — the reason that
/// matters more — a window filter is the only way to photograph a window that
/// something is standing in front of. The panel floats above the chat, so
/// "capture the chat" and "capture what is on top of the chat" are different
/// questions and only one of them has the answer the product needs.
final class ChatWindowCapture {
    static let shared = ChatWindowCapture()

    /// The window chosen last time.
    ///
    /// Held across calls on purpose: this chat application keeps several windows
    /// of the same size, and re-choosing on every tick lets the target jump between
    /// them — the frame lands on a different conversation than the geometry the
    /// caller is about to map against. A newly available *main* window still wins,
    /// because that is a real change rather than a re-selection.
    private var lastWindowId: CGWindowID?

    // MARK: - Permissions

    /// Whether the system has granted Screen Recording to this application.
    ///
    /// Worth asking out loud rather than inferring: without the grant macOS blanks
    /// every window's title, so "no target found" is what a missing permission
    /// looks like from the outside, and a user staring at a panel that vanished
    /// for no stated reason has no way to guess.
    func screenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Asks the system to show the Screen Recording prompt. Once per app identity.
    @discardableResult
    func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Target

    /// The chat window to capture, or nil when there is none.
    func findTargetWindow() async throws -> CGWindowID? {
        guard screenRecordingGranted() else {
            throw CaptureError.screenRecordingDenied
        }
        let content = try await Self.content()
        let candidates = content.windows.filter { ChatWindowCapture.isChatWindow($0) }
        guard !candidates.isEmpty else {
            return nil
        }

        if let held = lastWindowId,
           candidates.contains(where: { $0.windowID == held }) {
            return held
        }
        // Sorted with an explicit total order: `sorted` is not stable, and two
        // equally good windows must not swap places between frames.
        let best = candidates.sorted { a, b in
            let rankA = ChatWindowCapture.rank(a)
            let rankB = ChatWindowCapture.rank(b)
            if rankA.main != rankB.main {
                return rankA.main
            }
            if rankA.area != rankB.area {
                return rankA.area > rankB.area
            }
            return a.windowID < b.windowID
        }.first
        lastWindowId = best?.windowID
        return best?.windowID
    }

    /// One frame of [windowId], or of the display when it is nil.
    ///
    /// [excluding] lists this application's own windows. It only matters for a
    /// display capture — a window capture cannot contain anything that is not that
    /// window — but the panel still leaves the screen before every shot, because a
    /// panel that is merely behind the camera is a panel that flickers.
    func capture(windowId: CGWindowID?, excluding excluded: [CGWindowID]) async throws -> CapturedFrame {
        let content = try await Self.content()

        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.scalesToFit = false

        let filter: SCContentFilter
        let origin: CGPoint
        let pointSize: CGSize

        if let windowId {
            guard let window = content.windows.first(where: { $0.windowID == windowId }) else {
                throw CaptureError.windowVanished
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            origin = window.frame.origin
            pointSize = window.frame.size
            configuration.width = max(1, Int(window.frame.width.rounded()))
            configuration.height = max(1, Int(window.frame.height.rounded()))
        } else {
            guard let display = content.displays.first else {
                throw CaptureError.noImage("没有可截取的显示器")
            }
            let own = excluded.compactMap { id in content.windows.first { $0.windowID == id } }
            filter = SCContentFilter(display: display, excludingWindows: own)
            origin = .zero
            pointSize = CGSize(width: display.width, height: display.height)
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return try ChatWindowCapture.frame(from: image, origin: origin, pointSize: pointSize)
    }

    // MARK: - Choosing

    /// Is this the chat window rather than one of the application's other windows?
    ///
    /// The size floor is the discriminator: a detached utility window is small, and
    /// a small window that happened to be capturable would otherwise be read as a
    /// conversation.
    static func isChatWindow(_ window: SCWindow) -> Bool {
        let owner = window.owningApplication?.applicationName ?? ""
        guard owner.localizedCaseInsensitiveContains("WeChat") || owner.contains("微信") else {
            return false
        }
        return window.frame.width >= 600 && window.frame.height >= 400
    }

    /// A window whose title is the application's own name is the main chat window,
    /// and beats a larger detached one of the same application.
    private static let mainTitles: Set<String> = ["微信", "WeChat"]

    private static func rank(_ window: SCWindow) -> (main: Bool, area: Double) {
        let title = window.title ?? ""
        return (mainTitles.contains(title), window.frame.width * window.frame.height)
    }

    // MARK: - Pixels

    private static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
    }

    private static func frame(from image: CGImage, origin: CGPoint, pointSize: CGSize) throws -> CapturedFrame {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw CaptureError.noImage("截屏读不出画面")
        }
        var pixels = Data(count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }
            // A bitmap context counts rows from the bottom. Flipping here means the
            // first row of the buffer is the top of the window, which is the frame
            // every rectangle in this file is already expressed in.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            throw CaptureError.noImage("截屏缓冲区建立失败")
        }
        return CapturedFrame(
            pixels: pixels,
            width: width,
            height: height,
            scaleX: pointSize.width > 0 ? Double(width) / pointSize.width : 1,
            scaleY: pointSize.height > 0 ? Double(height) / pointSize.height : 1,
            originX: Double(origin.x),
            originY: Double(origin.y)
        )
    }
}
