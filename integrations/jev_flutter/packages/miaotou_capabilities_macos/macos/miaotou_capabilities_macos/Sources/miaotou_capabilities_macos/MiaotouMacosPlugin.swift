import Cocoa
import FlutterMacOS
import Foundation

/// The macOS answers, as one plugin.
///
/// One class rather than four because the four are not independent: the capture
/// has to take the panel out of its own shot, and the panel is a window this class
/// creates. Split across four plugin classes they would be four objects holding
/// one window between them, and the order in which the panel is hidden and the
/// frame is taken would become an argument instead of a fact.
public class MiaotouMacosPlugin: NSObject, FlutterPlugin {
    /// Shared with `native.dart`. Renaming it is a runtime `MissingPluginException`
    /// on a machine where nobody is watching, which is why the Dart side asserts
    /// both names.
    static let methodChannelName = "miaotoujunshi/macos"
    static let eventChannelName = "miaotoujunshi/macos/events"

    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MiaotouMacosPlugin()

        let channel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger
        )
        registrar.addMethodCallDelegate(instance, channel: channel)

        let events = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger
        )
        events.setStreamHandler(MiaotouMacosEventHandler(sink: { sink in
            // One write point for the sink. Two would be two places that look like
            // they decide where a panel event goes, and only one of them would be
            // the one that runs when the panel is cancelled.
            instance.eventSink = sink
            FloatingPanelHost.shared.onEvent = { event in
                // The window server delivers drags and taps on the main thread and
                // so does the timer that reads a window's frame; the channel is not
                // allowed to be written from anywhere else.
                DispatchQueue.main.async { sink?(event) }
            }
        }))
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "findTargetWindow":
            findTargetWindow(result)
        case "capture":
            capture(arguments: arguments, result: result)
        case "recognize":
            recognize(arguments: arguments, result: result)
        case "inject":
            inject(arguments: arguments, result: result)
        case "panelGeometry":
            DispatchQueue.main.async { result(FloatingPanelHost.shared.geometry()) }
        case "panel.show":
            DispatchQueue.main.async {
                let rect = MiaotouMacosPlugin.rect(arguments["window"])
                FloatingPanelHost.shared.show(
                    anchor: arguments["anchor"] as? String ?? "topLeft",
                    dx: MiaotouMacosPlugin.number(arguments["dx"]),
                    dy: MiaotouMacosPlugin.number(arguments["dy"]),
                    at: rect
                )
                result(nil)
            }
        case "panel.restore":
            DispatchQueue.main.async {
                FloatingPanelHost.shared.restore()
                result(nil)
            }
        case "panel.hide":
            DispatchQueue.main.async { result(FloatingPanelHost.shared.hide()) }
        case "panel.focusable":
            DispatchQueue.main.async {
                FloatingPanelHost.shared.setFocusable(arguments["value"] as? Bool ?? false)
                result(nil)
            }
        case "requestPermissions":
            // Answered out loud rather than inferred. Without Screen Recording the
            // system blanks every window's title, so a missing target looks exactly
            // like a chat window that is not there.
            let recording = ChatWindowCapture.shared.screenRecordingGranted()
            if !recording {
                _ = ChatWindowCapture.shared.requestScreenRecording()
            }
            _ = AccessibilityDraft.shared.requestAccessibility()
            result([
                "screenRecording": recording,
                "accessibility": AccessibilityDraft.shared.hasAccessibility(),
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Capture

    private func findTargetWindow(_ result: @escaping FlutterResult) {
        Task {
            do {
                let windowId = try await ChatWindowCapture.shared.findTargetWindow()
                await MainActor.run {
                    result(windowId.map { String($0) })
                }
            } catch {
                await MainActor.run { result(nil) }
            }
        }
    }

    private func capture(arguments: [String: Any], result: @escaping FlutterResult) {
        let windowId = (arguments["windowId"] as? String).flatMap { UInt32($0) }
        let excluded = FloatingPanelHost.shared.ownWindowIds
        Task {
            do {
                let frame = try await ChatWindowCapture.shared.capture(
                    windowId: windowId,
                    excluding: excluded
                )
                await MainActor.run {
                    result([
                        "ok": true,
                        "pixels": FlutterStandardTypedData(bytes: frame.pixels),
                        "width": frame.width,
                        "height": frame.height,
                        "scaleX": frame.scaleX,
                        "scaleY": frame.scaleY,
                        "originX": frame.originX,
                        "originY": frame.originY,
                    ])
                }
            } catch let error as CaptureError {
                await MainActor.run {
                    result([
                        "ok": false,
                        "code": MiaotouMacosPlugin.code(for: error),
                        "message": MiaotouMacosPlugin.message(for: error),
                    ])
                }
            } catch {
                await MainActor.run {
                    result([
                        "ok": false,
                        "code": 1,
                        "message": "截屏失败：\(error.localizedDescription)",
                    ])
                }
            }
        }
    }

    private func recognize(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let typed = arguments["pixels"] as? FlutterStandardTypedData,
              let width = arguments["width"] as? Int,
              let height = arguments["height"] as? Int,
              let image = MiaotouMacosPlugin.image(from: typed, width: width, height: height) else {
            result(FlutterError(
                code: "bad_frame",
                message: "读不出这一帧的画面",
                details: nil
            ))
            return
        }
        let languages = arguments["languages"] as? [String] ?? ["zh-Hans"]
        do {
            let lines = try VisionTextReader.shared.recognize(image: image, languages: languages)
            result(lines.map { $0.dictionary })
        } catch {
            result(FlutterError(
                code: "ocr_failed",
                message: "文字识别失败：\(error.localizedDescription)",
                details: nil
            ))
        }
    }

    // MARK: - Injection

    private func inject(arguments: [String: Any], result: @escaping FlutterResult) {
        let text = arguments["text"] as? String ?? ""
        guard let raw = arguments["windowId"] as? String, let windowId = UInt32(raw) else {
            result(["verified": false, "reason": "没有指定目标窗口"])
            return
        }
        // The write is on the main thread because the accessibility tree is only
        // safe to touch from it.
        DispatchQueue.main.async {
            result(AccessibilityDraft.shared.fill(text, intoWindow: windowId).dictionary)
        }
    }

    // MARK: - Helpers

    /// Rebuilds the bitmap the capture sent over.
    ///
    /// The bytes make the round trip rather than being kept on this side of the
    /// channel: a frame identifier would be a second thing to get wrong, and the
    /// caller already holds the exact frame it wants read.
    static func image(from typed: FlutterStandardTypedData, width: Int, height: Int) -> CGImage? {
        let data = typed.data
        guard width > 0, height > 0, data.count == width * height * 4 else {
            return nil
        }
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func code(for error: CaptureError) -> Int {
        switch error {
        case .screenRecordingDenied:
            return 1
        case .windowVanished:
            return 2
        case .noImage:
            return 3
        }
    }

    static func message(for error: CaptureError) -> String {
        switch error {
        case .screenRecordingDenied:
            return "未授予屏幕录制权限，请到系统设置里打开后重新启动"
        case .windowVanished:
            return "目标窗口已经不在屏幕上"
        case .noImage(let detail):
            return "截屏失败：\(detail)"
        }
    }

    static func rect(_ raw: Any?) -> CGRect? {
        guard let map = raw as? [String: Any],
              let left = map["left"] as? Double,
              let top = map["top"] as? Double,
              let right = map["right"] as? Double,
              let bottom = map["bottom"] as? Double else {
            return nil
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func number(_ raw: Any?) -> Double {
        (raw as? NSNumber)?.doubleValue ?? 0
    }
}

/// Keeps the event channel's sink alive for as long as somebody is listening.
private final class MiaotouMacosEventHandler: NSObject, FlutterStreamHandler {
    private let onSink: (FlutterEventSink?) -> Void

    init(sink: @escaping (FlutterEventSink?) -> Void) {
        self.onSink = sink
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onSink(nil)
        return nil
    }
}
