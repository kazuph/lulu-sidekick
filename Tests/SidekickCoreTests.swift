import XCTest
import Foundation
@testable import SidekickCore

final class AlertParserTests: XCTestCase {
    let staticTexts = ["Details & Options", "curl", "pid:", "args:", "path:", "51090", "port/protocol:", "ip address:",
                       "Connection:", "(reverse) dns:", "Rule Scope:", "Rule Duration:", "Process:",
                       "curl -fL -o /tmp/x.dmg https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg",
                       "185.199.109.153", "443 (TCP)", ":", "Time stamp: 12:07:13"]
    let textAreas = ["/usr/bin/curl", "unknown", "is connecting to github.com"]

    func testParsesSample() {
        let f = AlertParser.parse(staticTexts: staticTexts, textAreas: textAreas)
        XCTAssertEqual(f.processName, "curl")
        XCTAssertEqual(f.pid, 51090)
        XCTAssertEqual(f.path, "/usr/bin/curl")
        XCTAssertEqual(f.args, "curl -fL -o /tmp/x.dmg https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg")
        XCTAssertEqual(f.destHost, "github.com")
        XCTAssertEqual(f.ip, "185.199.109.153")
        XCTAssertEqual(f.port, "443 (TCP)")
        XCTAssertEqual(f.reverseDNS, "unknown")
        XCTAssertEqual(f.timestamp, "12:07:13")
        XCTAssertEqual(f.key, "51090@12:07:13")
    }

    func testOrderIndependent() {
        let f = AlertParser.parse(staticTexts: staticTexts.reversed().map { $0 }, textAreas: textAreas.reversed())
        XCTAssertEqual(f.pid, 51090); XCTAssertEqual(f.ip, "185.199.109.153")
        XCTAssertEqual(f.destHost, "github.com"); XCTAssertEqual(f.path, "/usr/bin/curl")
        XCTAssertEqual(f.port, "443 (TCP)"); XCTAssertEqual(f.timestamp, "12:07:13")
    }

    func testIPOnlyDestinationAndReverseDNS() {
        let f = AlertParser.parse(staticTexts: staticTexts, textAreas: ["/usr/bin/curl", "cdn-185-199-109-153.github.com", "is connecting to 185.199.109.153"])
        XCTAssertEqual(f.destHost, "185.199.109.153")
        XCTAssertEqual(f.reverseDNS, "cdn-185-199-109-153.github.com")
    }

    func testNoArgs() {
        var st = staticTexts; st.remove(at: st.firstIndex(of: "Process:")! + 1)
        let f = AlertParser.parse(staticTexts: st, textAreas: textAreas)
        XCTAssertNil(f.args)
        XCTAssertEqual(f.ip, "185.199.109.153")
    }

    func testIncompleteHasNoKey() {
        XCTAssertNil(AlertParser.parse(staticTexts: ["Details & Options", "curl"], textAreas: []).key)
    }
}

final class InvestigatorTests: XCTestCase {
    func testChainOfLiveProcess() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep"); p.arguments = ["30"]
        try p.run(); defer { p.terminate(); p.waitUntilExit() }
        let chain = Investigator.parentChain(pid: p.processIdentifier, processName: "sleep")
        XCTAssertNil(chain.note, "note=\(chain.note ?? "")")
        XCTAssertEqual(chain.entries.first?.pid, p.processIdentifier)
        XCTAssertTrue(chain.entries.first?.command.contains("sleep 30") ?? false)
        XCTAssertEqual(chain.entries.dropFirst().first?.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(chain.entries.last?.pid, 1)
        print("CHAIN:", chain.entries.map { "\($0.pid) \($0.command)" }.joined(separator: " <- "))
    }

    func testChainOfDeadPid() {
        let chain = Investigator.parentChain(pid: 99999, processName: "curl")
        XCTAssertTrue(chain.entries.isEmpty)
        XCTAssertEqual(chain.note, "pid 99999 は終了済みで追えない")
    }

    func testPidReuseTreatedAsGone() throws {
        // 生きている別プロセスの pid を、違う名前で問い合わせる
        let chain = Investigator.parentChain(pid: ProcessInfo.processInfo.processIdentifier, processName: "curl-not-me")
        XCTAssertTrue(chain.entries.isEmpty)
        XCTAssertTrue(chain.note?.contains("再利用") ?? false)
    }

    func testSignatureOfCurlIsApple() {
        let s = Investigator.signature(path: "/usr/bin/curl")
        XCTAssertTrue(s.signed); XCTAssertTrue(s.isApple); XCTAssertEqual(s.identifier, "com.apple.curl")
    }

    func testSignatureMissingAndUnsigned() {
        XCTAssertFalse(Investigator.signature(path: "/nonexistent/x").signed)
        let tmp = NSTemporaryDirectory() + "unsigned-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: tmp, contents: Data([0, 1, 2]))
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        XCTAssertFalse(Investigator.signature(path: tmp).signed)
    }

    func testDestination() {
        let f = AlertFacts(args: "curl https://github.com/x", destHost: "github.com", ip: "185.199.109.153")
        let d = Investigator.destination(facts: f, resolver: { _ in (["140.82.1.1", "185.199.109.153"], nil) })
        XCTAssertEqual(d?.ipMatchesHost, true); XCTAssertEqual(d?.argsContainHost, true)
        let d2 = Investigator.destination(facts: AlertFacts(args: "curl https://evil.example", destHost: "github.com", ip: "9.9.9.9"),
                                          resolver: { _ in (["140.82.1.1"], nil) })
        XCTAssertEqual(d2?.ipMatchesHost, false); XCTAssertEqual(d2?.argsContainHost, false)
        let d3 = Investigator.destination(facts: AlertFacts(destHost: "1.2.3.4", ip: "1.2.3.4"))
        XCTAssertEqual(d3?.hostIsIPOnly, true); XCTAssertNil(d3?.ipMatchesHost)
    }
}

final class JudgeTests: XCTestCase {
    func testParseVerdict() {
        let ok = #"```json\#n{"verdict":"許可してよい","why":"理由"}\#n```"#
        XCTAssertEqual(try? Judge.parseVerdict(ok).get().why, "理由")
        XCTAssertThrowsError(try Judge.parseVerdict(#"{"verdict":"たぶん","why":""}"#).get())
        XCTAssertThrowsError(try Judge.parseVerdict("no json").get())
    }

    func testFactsTextAndSummary() {
        let f = AlertFacts(processName: "curl", pid: 1, path: "/usr/bin/curl", destHost: "github.com", ip: "1.1.1.1", port: "443 (TCP)")
        let chain = ParentChain(entries: [ChainEntry(pid: 3, command: "/usr/bin/curl -fL x"), ChainEntry(pid: 2, command: "-zsh"), ChainEntry(pid: 1, command: "/sbin/launchd")])
        let t = Judge.factsText(f, Investigation(chain: chain))
        XCTAssertTrue(t.contains("github.com")); XCTAssertTrue(t.contains("pid 2: -zsh"))
        XCTAssertEqual(Summary.chainLine(chain), "launchd → -zsh → curl x")
    }

    func testURLsAreExtractedInFull() {
        let long = "https://generativelanguage.googleapis.com/v1beta/models/gemini-4-hydrogen"
        let f = AlertFacts(processName: "curl", pid: 1, path: "/usr/bin/curl",
                           args: Redactor.redact("-s -H x-goog-api-key: AIzaSyBNlwJHxxxxxxxxxxxxxxxxxxxxxxxxxxx \(long)"))
        let chain = ParentChain(entries: [ChainEntry(pid: 1, command: "curl -s \"\(long)\" https://example.com/a?b=1,"), ChainEntry(pid: 0, command: "-zsh")])
        XCTAssertEqual(Summary.urls(f, chain), [long, "https://example.com/a?b=1"])
        XCTAssertFalse(f.args!.contains("AIza"))
        XCTAssertEqual(Summary.urls(AlertFacts(processName: "x", args: "-v"), nil), [])
    }

    /// 実際に claude CLI を呼ぶ。RUN_CLAUDE=1 のときだけ。
    func testRealClaude() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CLAUDE"] == "1")
        let f = AlertFacts(processName: "curl", pid: 51090, path: "/usr/bin/curl",
                           args: "curl -fL -o /tmp/App-1.0.0.dmg https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg",
                           destHost: "github.com", ip: "185.199.109.153", port: "443 (TCP)", reverseDNS: "unknown", timestamp: "12:07:13")
        let chain = ParentChain(entries: [
            ChainEntry(pid: 51090, command: "/usr/bin/curl -fL -o /tmp/App-1.0.0.dmg https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg"),
            ChainEntry(pid: 51080, command: "ruby brew.rb upgrade --cask example/tap/app"),
            ChainEntry(pid: 51000, command: "-zsh"), ChainEntry(pid: 50990, command: "claude"), ChainEntry(pid: 1, command: "/sbin/launchd")])
        let inv = Investigation(chain: chain,
                                signature: SignatureInfo(signed: true, identifier: "com.apple.curl", authorities: ["Software Signing"], isApple: true),
                                destination: DestinationCheck(hostIsIPOnly: false, resolvedIPs: ["185.199.109.153"], resolveError: nil, ipMatchesHost: true, argsContainHost: true))
        let v = try Judge.judge(facts: f, investigation: inv).get()
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        print("VERDICT_JSON:", String(decoding: try enc.encode(v), as: UTF8.self))
        // 失敗時の表示確認用: 存在しない claude
        if case .success = Judge.judge(facts: f, investigation: inv, claude: "/nonexistent/claude") { XCTFail() }
    }
}

final class RecommenderTests: XCTestCase {
    let ok = Verdict(verdict: "許可してよい", why: "x")
    let apple = SignatureInfo(signed: true, identifier: "com.apple.curl", authorities: ["Software Signing"], isApple: true)
    let teamApp = SignatureInfo(signed: true, identifier: "com.foo.app", teamIdentifier: "ABCDE12345", authorities: ["Developer ID Application: Foo"])
    let adhoc = SignatureInfo(signed: true, identifier: "foo", authorities: [], adhoc: true)

    func testCurlIsRemoteEndpointAlways() {
        let f = AlertFacts(processName: "curl", path: "/usr/bin/curl", destHost: "github.com", ip: "1.2.3.4")
        let r = Recommender.recommend(facts: f, signature: apple, verdict: ok)   // Apple 製の署名でも汎用コマンドは Remote Endpoint
        XCTAssertEqual(r.scope, "Remote Endpoint"); XCTAssertEqual(r.duration, "Always")
        XCTAssertEqual(r.displayLine, "Rule Scope: Remote Endpoint ／ Duration: Always")
    }
    func testGenericNames() {
        for n in ["python3.12", "node", "ruby", "bash", "osascript", "git", "wget", "ssh", "perl", "zsh", "sh", "nc"] {
            XCTAssertEqual(Recommender.scope(facts: AlertFacts(processName: n, path: "/x/\(n)"), signature: teamApp), "Remote Endpoint", n)
        }
    }
    func testIPOnlyIsOnce() {
        XCTAssertEqual(Recommender.duration(facts: AlertFacts(destHost: "185.199.109.153", ip: "185.199.109.153")), "Once")
        XCTAssertEqual(Recommender.duration(facts: AlertFacts(destHost: "2606:4700::1", ip: "2606:4700::1")), "Once")
        XCTAssertEqual(Recommender.duration(facts: AlertFacts()), "Once")
    }
    func testSignedAppIsProcess() {
        let f = AlertFacts(processName: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack", destHost: "slack.com")
        XCTAssertEqual(Recommender.scope(facts: f, signature: teamApp), "Process")
        XCTAssertEqual(Recommender.scope(facts: f, signature: apple), "Process")
    }
    func testAdhocUnsignedUnknownIsRemoteEndpoint() {
        let f = AlertFacts(processName: "myapp", path: "/Users/x/myapp", destHost: "a.example")
        XCTAssertEqual(Recommender.scope(facts: f, signature: adhoc), "Remote Endpoint")
        XCTAssertEqual(Recommender.scope(facts: f, signature: SignatureInfo(signed: false, error: "未署名")), "Remote Endpoint")
        XCTAssertEqual(Recommender.scope(facts: f, signature: nil), "Remote Endpoint")
    }
    func testCautionShowsBlock() {
        let f = AlertFacts(processName: "curl", path: "/usr/bin/curl", destHost: "github.com")
        for v in ["要注意", "ブロック推奨"] {
            let r = Recommender.recommend(facts: f, signature: apple, verdict: Verdict(verdict: v, why: "x"))
            XCTAssertTrue(r.advisesBlock)
            XCTAssertEqual(r.displayLine, "Block（または起動元を確かめてから Once で Allow）")
        }
    }
}

final class RedactorTests: XCTestCase {
    let M = Redactor.mask
    func r(_ s: String) -> String { Redactor.redact(s) }

    func testAuthorizationHeader() {
        XCTAssertEqual(r("curl --header Authorization: Bearer abc.DEF-123_xyz https://api.example.com/v1"),
                       "curl --header Authorization: Bearer \(M) https://api.example.com/v1")
        XCTAssertEqual(r("curl -H Authorization: token gh" + "p_abcdefghijklmnopqrstuvwxyz0123 https://api.github.com"),
                       "curl -H Authorization: token \(M) https://api.github.com")
    }
    func testApiKeyHeaderAndCookie() {
        XCTAssertEqual(r("curl -H X-Api-Key: s3cr3tvalue https://a.example"), "curl -H X-Api-Key: \(M) https://a.example")
        XCTAssertEqual(r("curl -H Cookie: sid=abc; csrf=def --silent https://a.example"),
                       "curl -H Cookie: \(M) --silent https://a.example")
    }
    func testUserinfoAndUserFlag() {
        XCTAssertEqual(r("git clone https://bob:hunter2@git.example.com/r.git"), "git clone https://bob:\(M)@git.example.com/r.git")
        XCTAssertEqual(r("curl -u bob" + ":hunter2 https://a.example"), "curl -u bob:\(M) https://a.example")
    }
    func testKeyValueParams() {
        XCTAssertEqual(r("curl https://a.example/x?api_key=AAA111&page=2"), "curl https://a.example/x?api_key=\(M)&page=2")
        XCTAssertEqual(r("tool --password=hunter2 --token abc123 --verbose"), "tool --password=\(M) --token \(M) --verbose")
    }
    func testKnownTokenShapes() {
        XCTAssertEqual(r("x sk-" + "ant-abcdefghijklmnopqrstuvwx y"), "x \(M) y")
        XCTAssertEqual(r("x github" + "_pat_11ABCDEFG0123456789_abcdefghij y"), "x \(M) y")
        XCTAssertEqual(r("x AKIA" + "ABCDEFGHIJKLMNOP y"), "x \(M) y")
        XCTAssertEqual(r("x eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.SflKxwRJSMeKKF2Q y"), "x \(M) y")
    }
    func testKeepsOrdinaryArgs() {
        // Homebrew の実際の引数（秘密なし）は変えない。ホスト名も残る。
        let brew = "-q --retry 3 --silent --max-time 3 --location --output /dev/null --write-out %{http_code} --header X-GitHub-Api-Version:2022-11-28 --header Accept: application/vnd.github.sha --header If-None-Match: \"1cd7b3e1341b257955f5d31106637d7696019129\" https://api.github.com/repos/Homebrew/brew/commits/main"
        XCTAssertEqual(r(brew), brew)
        let dl = "--disable --cookie /dev/null --globoff --show-error --head https://github.com/example/app/releases/download/v1.0.0/App-1.0.0.dmg"
        XCTAssertEqual(r(dl), dl)
    }
    func testFactsAndChain() {
        let f = AlertFacts(processName: "curl", path: "/usr/bin/curl", args: "curl -H Authorization: Bearer zzz https://a.example", destHost: "a.example")
        XCTAssertEqual(Redactor.redact(f).args, "curl -H Authorization: Bearer \(M) https://a.example")
        XCTAssertEqual(Redactor.redact(f).destHost, "a.example")
        let c = ParentChain(entries: [ChainEntry(pid: 1, command: "tool --token abc")], note: "n")
        XCTAssertEqual(Redactor.redact(c).entries[0].command, "tool --token \(M)")
        XCTAssertEqual(Redactor.redact(c).note, "n")
    }
}

final class FindClaudeTests: XCTestCase {
    func testEnvOverride() {
        XCTAssertEqual(Judge.findClaude(env: ["LULU_SIDEKICK_CLAUDE": "/x/claude"], home: "/h", isExecutable: { $0 == "/x/claude" }), "/x/claude")
        XCTAssertNil(Judge.findClaude(env: ["LULU_SIDEKICK_CLAUDE": "/x/claude"], home: "/h", isExecutable: { _ in false }))
    }
    func testPathThenCommonDirs() {
        XCTAssertEqual(Judge.findClaude(env: ["PATH": "/a:/b"], home: "/h", isExecutable: { $0 == "/b/claude" }), "/b/claude")
        XCTAssertEqual(Judge.findClaude(env: ["PATH": "/usr/bin"], home: "/h", isExecutable: { $0 == "/h/.local/bin/claude" }), "/h/.local/bin/claude")
        XCTAssertNil(Judge.findClaude(env: [:], home: "/h", isExecutable: { _ in false }))
    }
    func testMissingClaudeFailsClearly() {
        let f = AlertFacts(processName: "curl", path: "/usr/bin/curl", destHost: "a.example")
        let inv = Investigation(chain: ParentChain(entries: []))
        guard case .failure(let e) = Judge.judge(facts: f, investigation: inv, claude: nil) else { return XCTFail() }
        XCTAssertTrue(e.message.contains("見つからない"))
    }
}
