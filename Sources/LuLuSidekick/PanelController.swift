import AppKit
import SidekickCore

/// 通知の横に出す枠なしパネル。フォーカスを奪わず、クリックも通さない。
final class PanelController {
    static let width: CGFloat = 360
    let panel: NSPanel
    private let stack = NSStackView()
    private let bg = NSView()
    private(set) var size = NSSize(width: PanelController.width, height: 120)
    /// LuLu 通知ウィンドウの枠（Cocoa 座標）。nil なら画面中央（demo）。
    var anchor: NSRect?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // LuLu の通知は NSPopUpMenuWindowLevel(101)。それより上。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true

        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 0.97).cgColor
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor
        panel.contentView = bg

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: bg.topAnchor, constant: 12),
        ])
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.isSelectable = false
        l.preferredMaxLayoutWidth = Self.width - 28
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: Self.width - 28).isActive = true
        return l
    }

    private func section(_ title: String, _ body: String, charWrap: Bool = false) {
        let t = label(title, size: 10, weight: .semibold, color: NSColor(calibratedWhite: 0.6, alpha: 1))
        stack.addArrangedSubview(t)
        stack.setCustomSpacing(1, after: t)
        let b = label(body, size: 12)
        // URL のように空白の無い長い文字列は、単語の区切りを待たずに文字単位で折り返して全部見せる
        if charWrap { b.lineBreakMode = .byCharWrapping; b.cell?.wraps = true }
        stack.addArrangedSubview(b)
        stack.setCustomSpacing(7, after: b)
    }

    func update(facts: AlertFacts, investigation: Investigation?, state: JudgeState) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }

        // 1行目: 判定
        switch state {
        case .pending:
            let l = label("● 判定中…", size: 16, weight: .bold, color: .systemGray); stack.addArrangedSubview(l)
        case .failed(let m):
            let l = label("● AIの判定に失敗", size: 16, weight: .bold, color: .systemOrange); stack.addArrangedSubview(l)
            let w = label(m, size: 12, color: NSColor(calibratedWhite: 0.85, alpha: 1)); stack.addArrangedSubview(w)
        case .done(let v):
            let color: NSColor = v.verdict == "許可してよい" ? .systemGreen : (v.verdict == "要注意" ? .systemYellow : .systemRed)
            let l = label("● \(v.verdict)", size: 16, weight: .bold, color: color); stack.addArrangedSubview(l)
            let w = label(v.why, size: 13); stack.addArrangedSubview(w)
            stack.setCustomSpacing(8, after: w)
            section("おすすめ", Recommender.recommend(facts: facts, signature: investigation?.signature, verdict: v).displayLine)
        }
        if case .done = state {} else { if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(8, after: last) } }

        if let inv = investigation {
            section("起動元", Summary.chainLine(inv.chain))
        } else {
            section("起動元", "調べています…")
        }
        // 行き先: 引数に出てくる URL を省略せずに先頭へ、その下に通知のホスト・IP・ポートと正引きの照合
        let urls = Summary.urls(facts, investigation?.chain)
        let dest = Summary.destinationLine(facts, investigation?.destination)
        section("行き先", (urls + [dest]).joined(separator: "\n"), charWrap: true)

        bg.layoutSubtreeIfNeeded()
        let h = stack.fittingSize.height + 24
        size = NSSize(width: Self.width, height: ceil(h))
        panel.setContentSize(size)
        reposition()
    }

    func reposition() {
        var origin: NSPoint
        if let a = anchor {
            let screen = NSScreen.screens.first(where: { $0.frame.intersects(a) }) ?? NSScreen.main ?? NSScreen.screens[0]
            let vf = screen.visibleFrame
            var x = a.minX - Self.width - 10
            var y = a.maxY - size.height     // 通知の上端にそろえる
            if x < vf.minX {                 // 左にはみ出すなら下
                x = a.minX
                y = a.minY - size.height - 10
            }
            x = max(vf.minX, min(x, vf.maxX - Self.width))
            y = max(vf.minY, min(y, vf.maxY - size.height))
            origin = NSPoint(x: x, y: y)
        } else {
            let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            origin = NSPoint(x: vf.midX - Self.width / 2, y: vf.midY - size.height / 2)
        }
        panel.setFrameOrigin(origin)
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }
}
