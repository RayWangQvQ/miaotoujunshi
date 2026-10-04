import AppKit
import ApplicationServices
import Foundation

/// What one attempt to put a draft in the chat's input box produced.
struct DraftOutcome {
    let verified: Bool
    let text: String
    let reason: String?

    var dictionary: [String: Any] {
        var payload: [String: Any] = ["verified": verified]
        if verified {
            payload["text"] = text
        } else {
            payload["reason"] = reason ?? "写入失败"
        }
        return payload
    }
}

/// Putting text into another application's input field, and proving it landed.
///
/// **There is no send path here and no way to add one.** Nothing in this file
/// posts a key event, performs an accessibility action, or touches the return
/// key; the only write is `AXUIElementSetAttributeValue` on a text area. That is
/// not restraint, it is the reason this mechanism was chosen over pasting: a
/// synthesised `Cmd+V` reaches the *frontmost* application, so a panel that is
/// deliberately not frontmost would type the reply into somebody else's window,
/// and "the events were posted" is not something that can be read back.
///
/// The result is reported only after the text is read back out of the same
/// element. The application scans this file for the three send primitives, so
/// adding one is a failing test rather than a review's memory.
final class AccessibilityDraft {
    static let shared = AccessibilityDraft()

    /// The chat window is titled after the application; the other window it owns
    /// is untitled and holds no input box.
    private let chatWindowTitle = "微信"

    /// The message box is a text area. The sidebar's search field is one too —
    /// see `findInputBox` for why size decides between them.
    private let inputRole = kAXTextAreaRole

    /// Search field 127×23, message box 643×129 on the measured window: a factor of
    /// about 24, so this floor is not a close call. Anything smaller is refused
    /// rather than guessed at.
    private let minInputArea: Double = 10_000

    /// A busy chat window carries one node per visible message; this keeps a miss
    /// cheap instead of walking thousands of nodes.
    private let maxNodes = 2_000

    /// Short enough to swallow a double click, long enough that a deliberate retry
    /// a moment later goes through. Keyed on the input's *content*, so re-typing
    /// the same words after a pause still works.
    private let duplicateWindow: TimeInterval = 0.4
    private var lastFill: (text: String, at: Date)?

    // MARK: - Permissions

    func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system dialog that grants the Accessibility permission.
    @discardableResult
    func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Filling

    /// Writes [text] into the input box of the window named by [windowId].
    func fill(_ text: String, intoWindow windowId: CGWindowID) -> DraftOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DraftOutcome(verified: false, text: "", reason: "没有可填入的内容")
        }
        guard hasAccessibility() else {
            return DraftOutcome(verified: false, text: "", reason: "未授予辅助功能权限")
        }
        if let last = lastFill,
           last.text == trimmed,
           Date().timeIntervalSince(last.at) < duplicateWindow {
            return DraftOutcome(verified: false, text: "", reason: "刚填入过同样的内容，已忽略这次重复点击")
        }
        guard let pid = AccessibilityDraft.pid(for: windowId) else {
            return DraftOutcome(verified: false, text: "", reason: "没找到目标窗口")
        }
        guard let box = findInputBox(pid: pid) else {
            return DraftOutcome(verified: false, text: "", reason: "未取得可用的输入控件")
        }

        guard AXUIElementSetAttributeValue(box, kAXValueAttribute as CFString, trimmed as CFTypeRef)
                == .success else {
            return DraftOutcome(verified: false, text: "", reason: "写入输入框失败")
        }
        guard let readBack = AccessibilityDraft.value(of: box) else {
            return DraftOutcome(
                verified: false,
                text: "",
                reason: "写入后没读到内容，可能没填进去"
            )
        }
        guard readBack.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
            return DraftOutcome(verified: false, text: readBack, reason: "写入后内容不一致")
        }

        lastFill = (trimmed, Date())
        return DraftOutcome(verified: true, text: readBack, reason: nil)
    }

    // MARK: - Finding the box

    /// The application's largest text area, or nil.
    ///
    /// **Largest, not first.** The window holds two text areas and the sidebar's
    /// search field is shallower, so a first-match walk writes the reply into the
    /// search box — and a read-back check cannot catch it, because reading and
    /// writing both go through the same wrong element and agree with each other.
    /// Size is the only thing that separates them.
    ///
    /// The walk is breadth-first and bounded: a chat window carries a node per
    /// visible message, and an unbounded depth-first walk of one is how a miss
    /// becomes a hang.
    func findInputBox(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        guard let windows = AccessibilityDraft.attribute(
            application,
            kAXWindowsAttribute
        ) as? [AXUIElement], !windows.isEmpty else {
            return nil
        }
        let ordered = windows.sorted { lhs, rhs in
            let lhsTitle = AccessibilityDraft.attribute(lhs, kAXTitleAttribute) as? String
            let rhsTitle = AccessibilityDraft.attribute(rhs, kAXTitleAttribute) as? String
            if (lhsTitle == chatWindowTitle) != (rhsTitle == chatWindowTitle) {
                return lhsTitle == chatWindowTitle
            }
            return false
        }

        var best: AXUIElement?
        var bestArea: Double = 0
        for window in ordered {
            var queue: [AXUIElement] = [window]
            var seen = 0
            var index = 0
            while index < queue.count && seen < maxNodes {
                let element = queue[index]
                index += 1
                seen += 1
                if AccessibilityDraft.attribute(element, kAXRoleAttribute) as? String == inputRole {
                    let size = AccessibilityDraft.size(of: element)
                    let area = size.width * size.height
                    if area > bestArea {
                        best = element
                        bestArea = area
                    }
                }
                if let children = AccessibilityDraft.attribute(
                    element,
                    kAXChildrenAttribute
                ) as? [AXUIElement] {
                    queue.append(contentsOf: children)
                }
            }
        }
        guard bestArea >= minInputArea else {
            return nil
        }
        return best
    }

    // MARK: - Accessibility plumbing

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func value(of element: AXUIElement) -> String? {
        attribute(element, kAXValueAttribute) as? String
    }

    /// The element's size, in points.
    ///
    /// `AXValue` is a Core Foundation type, so `as? AXValue` is a cast the
    /// compiler knows always succeeds and refuses to compile as a *conditional*
    /// one. The type is checked by identifier instead — the honest test, and the
    /// one that keeps a size attribute of some other type from being read as
    /// whichever pair of numbers happened to be in the same registers.
    private static func size(of element: AXUIElement) -> CGSize {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &raw) == .success,
              let value = raw,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return .zero
        }
        let size = unsafeBitCast(value, to: AXValue.self)
        var result = CGSize.zero
        guard AXValueGetValue(size, .cgSize, &result) else {
            return .zero
        }
        return result
    }

    /// The process that owns a window.
    ///
    /// The accessibility API is addressed by application, not by window, so the
    /// capture's window handle has to be translated before it can be used to write.
    private static func pid(for windowId: CGWindowID) -> pid_t? {
        let options: CGWindowListOption = [.optionIncludingWindow]
        guard let infos = CGWindowListCopyWindowInfo(options, windowId) as? [[String: Any]],
              let first = infos.first else {
            return nil
        }
        guard let pid = first[kCGWindowOwnerPID as String] as? pid_t, pid > 0 else {
            return nil
        }
        return pid
    }
}
