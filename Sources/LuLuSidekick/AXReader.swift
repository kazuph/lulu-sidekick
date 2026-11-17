import AppKit
import ApplicationServices
import SidekickCore

/// Accessibility API で LuLu の「LuLu Alert」ウィンドウを読む。読むだけで、操作（押す・書く）はしない。
enum AX {
    static let luluPath = "/Applications/LuLu.app"

    static func luluApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == luluPath }
    }

    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func alertWindows(of app: NSRunningApplication) -> [AXUIElement] {
        let a = AXUIElementCreateApplication(app.processIdentifier)
        guard let wins = attr(a, kAXWindowsAttribute as String) as? [AXUIElement] else { return [] }
        return wins.filter { (attr($0, kAXTitleAttribute as String) as? String) == "LuLu Alert" }
    }

    /// ウィンドウ配下をたどって static text と text area の値を集める。
    static func collect(_ win: AXUIElement) -> (staticTexts: [String], textAreas: [String]) {
        var st: [String] = [], ta: [String] = []
        func walk(_ el: AXUIElement, _ depth: Int) {
            guard depth < 14 else { return }
            let role = attr(el, kAXRoleAttribute as String) as? String
            if role == kAXStaticTextRole as String, let v = attr(el, kAXValueAttribute as String) as? String { st.append(v) }
            else if role == kAXTextAreaRole as String, let v = attr(el, kAXValueAttribute as String) as? String { ta.append(v) }
            if let kids = attr(el, kAXChildrenAttribute as String) as? [AXUIElement] { for k in kids { walk(k, depth + 1) } }
        }
        walk(win, 0)
        return (st, ta)
    }

    /// ウィンドウの枠を Cocoa 座標（左下原点）で返す。
    static func frame(_ win: AXUIElement) -> NSRect? {
        guard let pv = attr(win, kAXPositionAttribute as String), let sv = attr(win, kAXSizeAttribute as String) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        let H = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: p.x, y: H - p.y - s.height, width: s.width, height: s.height)
    }
}
