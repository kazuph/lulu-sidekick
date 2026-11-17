import AppKit
import ApplicationServices
import ServiceManagement
import SidekickCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem?
    var monitor: Monitor?
    var demoPanel: PanelController?
    let args = CommandLine.arguments

    func applicationDidFinishLaunching(_ n: Notification) {
        let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        s.button?.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "LuLu Sidekick")
        let m = NSMenu()
        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        m.addItem(login)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        s.menu = m
        status = s
        loginMenuItem = login

        if args.contains("--demo") { runDemo(); return }

        // 初回だけ、ログイン時の自動起動に登録する。メニューで外したら、その後は勝手に戻さない。
        let d = UserDefaults.standard
        if !d.bool(forKey: "loginItemConfigured") {
            setLoginItem(true)
            d.set(true, forKey: "loginItemConfigured")
        }
        refreshLoginMenu()

        // アクセシビリティ許可の確認（ダイアログを出すだけ。許可はユーザーが押す）
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("LuLuSidekick: アクセシビリティの許可が未付与")
        }
        monitor = Monitor(); monitor?.start()
    }

    var loginMenuItem: NSMenuItem?

    @objc func toggleLoginItem(_ sender: NSMenuItem) {
        setLoginItem(SMAppService.mainApp.status != .enabled)
        refreshLoginMenu()
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            NSLog("LuLuSidekick: ログイン項目 \(on ? "登録" : "解除") status=\(SMAppService.mainApp.status.rawValue)")
        } catch {
            NSLog("LuLuSidekick: ログイン項目の\(on ? "登録" : "解除")に失敗: \(error)")
        }
    }

    func refreshLoginMenu() {
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func runDemo() {
        let facts = AlertFacts(processName: "curl", pid: 51090, path: "/usr/bin/curl",
                               args: "curl -fL -o /tmp/App-1.0.0.dmg https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg",
                               destHost: "github.com", ip: "185.199.109.153", port: "443 (TCP)", reverseDNS: "unknown", timestamp: "12:07:13")
        let chain = ParentChain(entries: [
            ChainEntry(pid: 51090, command: "/usr/bin/curl -fL -o /tmp/App-1.0.0.dmg https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg"),
            ChainEntry(pid: 51080, command: "ruby -W0 -I /opt/homebrew/Library/Homebrew brew.rb upgrade --cask example/tap/app"),
            ChainEntry(pid: 51000, command: "-zsh"),
            ChainEntry(pid: 50990, command: "claude"),
            ChainEntry(pid: 1, command: "/sbin/launchd"),
        ])
        let inv = Investigation(chain: chain,
                                signature: SignatureInfo(signed: true, identifier: "com.apple.curl", authorities: ["Software Signing"], isApple: true),
                                destination: DestinationCheck(hostIsIPOnly: false, resolvedIPs: ["185.199.109.153"], resolveError: nil, ipMatchesHost: true, argsContainHost: true))
        let verdict = Verdict(verdict: "許可してよい",
                              why: "claude 経由の brew upgrade から起動され、行き先 github.com が引数の URL と一致し、正引きの IP とも合っています。")
        let p = PanelController()
        p.update(facts: facts, investigation: inv, state: .done(verdict)); p.show()
        demoPanel = p
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                snapshot(p, to: path)
                // 実際の画面描画も、パネルのウィンドウだけを screencapture で撮る
                let alt = path.replacingOccurrences(of: ".png", with: "-screencapture.png")
                let r = Shell.run("/usr/sbin/screencapture", ["-l", "\(p.panel.windowNumber)", "-o", "-x", alt], timeout: 10)
                print("screencapture status=\(r.status) err=\(r.err)")
                NSApp.terminate(nil)
            }
        }
    }

    func snapshot(_ p: PanelController, to path: String) {
        guard let v = p.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)); print("saved \(path)") }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
