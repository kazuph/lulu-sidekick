import AppKit
import ApplicationServices
import SidekickCore

/// 1秒ごとに LuLu Alert を探し、新しい通知ごとに調査・判定・パネル表示を1回だけ行う。
final class Monitor {
    private struct Tracked { var element: AXUIElement; var key: String? }
    private var tracked: [Tracked] = []
    private var processed = Set<String>()
    private let queue = DispatchQueue(label: "lulu-sidekick.ax")
    private var timer: DispatchSourceTimer?
    private var panels: [String: PanelController] = [:]   // main スレッドだけで触る

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume(); timer = t
    }

    private func tick() {
        guard let app = AX.luluApp() else { reconcile(present: []); return }
        let wins = AX.alertWindows(of: app)
        var present: [Tracked] = []
        for w in wins {
            if var t = tracked.first(where: { CFEqual($0.element, w) }) {
                if t.key == nil { t.key = parseKey(w) }
                present.append(t)
            } else {
                present.append(Tracked(element: w, key: parseKey(w)))
            }
        }
        tracked = present
        reconcile(present: present.map { $0.key }.compactMap { $0 })
        for t in present {
            guard let key = t.key else { continue }
            let frame = AX.frame(t.element)
            if !processed.contains(key) {
                processed.insert(key)
                handle(window: t.element, frame: frame)
            } else if let f = frame {
                DispatchQueue.main.async { [weak self] in
                    if let p = self?.panels[key] { p.anchor = f; p.reposition() }
                }
            }
        }
    }

    private var facts: [String: AlertFacts] = [:]
    private func parseKey(_ w: AXUIElement) -> String? {
        let c = AX.collect(w)
        let f = AlertParser.parse(staticTexts: c.staticTexts, textAreas: c.textAreas)
        guard let key = f.key else { return nil }
        facts[key] = f
        return key
    }

    /// 消えたウィンドウのパネルを閉じる。
    private func reconcile(present: [String]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (k, p) in self.panels where !present.contains(k) { p.close(); self.panels[k] = nil }
        }
    }

    private func handle(window: AXUIElement, frame: NSRect?) {
        guard let key = tracked.first(where: { CFEqual($0.element, window) })?.key, let raw = facts[key] else { return }
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            // 引数の秘密は、パネル・AI・ログのどこにも出さない。生の値は行き先の照合（手順2）にだけ使う。
            let f = Redactor.redact(raw)
            // 1. 親の連鎖（curl はすぐ終わるので最初）
            var inv = Investigation(chain: Redactor.redact(raw.pid.map { Investigator.parentChain(pid: $0, processName: raw.processName) }
                                    ?? ParentChain(entries: [], note: "pid が読めない")))
            DispatchQueue.main.async {
                let p = PanelController(); p.anchor = frame
                self.panels[key] = p
                p.update(facts: f, investigation: inv, state: .pending); p.show()
            }
            // 2. 署名と行き先
            if let path = f.path { inv.signature = Investigator.signature(path: path) }
            inv.destination = Investigator.destination(facts: raw)
            let snap = inv
            DispatchQueue.main.async { self.panels[key]?.update(facts: f, investigation: snap, state: .pending) }
            // 3. AI の判定
            let state: JudgeState
            switch Judge.judge(facts: f, investigation: snap) {
            case .success(let v): state = .done(v)
            case .failure(let e): state = .failed("AIの判定に失敗: \(e.message)")
            }
            DispatchQueue.main.async { self.panels[key]?.update(facts: f, investigation: snap, state: state) }
            SidekickLog.append(facts: f, investigation: snap, state: state)
        }
    }
}
