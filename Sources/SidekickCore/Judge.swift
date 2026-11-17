import Foundation

public enum Judge {
    /// claude CLI の場所。環境変数 LULU_SIDEKICK_CLAUDE → PATH → よく入る場所、の順に探す。
    /// ログイン項目から起動すると PATH が短いので、よく入る場所も見る。見つからなければ nil（判定は失敗として表示する）。
    public static func findClaude(env: [String: String] = ProcessInfo.processInfo.environment,
                                  home: String = NSHomeDirectory(),
                                  isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        if let p = env["LULU_SIDEKICK_CLAUDE"], !p.isEmpty { return isExecutable(p) ? p : nil }
        let pathDirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        let common = [home + "/.local/bin", home + "/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        for d in pathDirs + common where !d.isEmpty {
            let p = d + "/claude"
            if isExecutable(p) { return p }
        }
        return nil
    }

    /// 事実の文章（LLM に渡す）。
    public static func factsText(_ f: AlertFacts, _ inv: Investigation) -> String {
        var L: [String] = []
        L.append("## LuLu の通知")
        L.append("- プロセス名: \(f.processName ?? "不明")  pid: \(f.pid.map(String.init) ?? "不明")")
        L.append("- パス: \(f.path ?? "不明")")
        L.append("- 引数全文: \(f.args ?? "（なし）")")
        L.append("- 行き先ホスト: \(f.destHost ?? "不明")  IP: \(f.ip ?? "不明")  ポート: \(f.port ?? "不明")  逆引き: \(f.reverseDNS ?? "不明")")
        L.append("- 時刻: \(f.timestamp ?? "不明")")
        L.append("")
        L.append("## 親プロセスの連鎖（通知のプロセス → 親 → … → launchd）")
        if inv.chain.entries.isEmpty { L.append("- （取得できず）") }
        for e in inv.chain.entries { L.append("- pid \(e.pid): \(e.command)") }
        if let n = inv.chain.note { L.append("- 注記: \(n)") }
        L.append("")
        L.append("## パスの署名")
        if let s = inv.signature {
            if !s.signed { L.append("- 署名なし/取得失敗: \(s.error ?? "不明")") }
            else {
                L.append("- Identifier: \(s.identifier ?? "なし")  TeamIdentifier: \(s.teamIdentifier ?? "なし")")
                L.append("- Authority: \(s.authorities.isEmpty ? "なし" : s.authorities.joined(separator: " > "))")
                L.append("- ad-hoc 署名: \(s.adhoc ? "はい" : "いいえ")  Apple 製: \(s.isApple ? "はい" : "いいえ")")
            }
        } else { L.append("- （調べていない）") }
        L.append("")
        L.append("## 行き先の確認")
        if let d = inv.destination {
            if d.hostIsIPOnly { L.append("- 行き先は IP のみ（ホスト名なし）。正引きでの照合はできない") }
            else {
                L.append("- 正引き結果: \(d.resolvedIPs.isEmpty ? "なし" : d.resolvedIPs.joined(separator: ", "))\(d.resolveError.map { "（\($0)）" } ?? "")")
                L.append("- 通知の IP が正引き結果に含まれる: \(d.ipMatchesHost.map { $0 ? "はい" : "いいえ" } ?? "判定不能")")
                L.append("- 引数に行き先ホストが出てくる: \(d.argsContainHost.map { $0 ? "はい" : "いいえ" } ?? "判定不能")")
            }
        } else { L.append("- （調べていない）") }
        return L.joined(separator: "\n")
    }

    public static let policy = """
    あなたは macOS のファイアウォール LuLu の通知を見て、ユーザーが許可してよいかを判定する助手です。ユーザーが判断するので、あなたは判定と理由と推奨設定だけを返します。
    判定の方針:
    - user-agent や引数の文字列は偽装できるので、単独の根拠にしない。
    - 親の連鎖が、ユーザー自身が起動した既知のツール（Terminal・ghostty・claude・codex・brew・git など）につながり、行き先が引数の URL と一致すれば「許可してよい」。
    - 親が追えない・未署名・行き先が引数と食い違う・見覚えのない場所のバイナリは「要注意」以上。
    - why は必ず1〜2文、全体で120字以内。
    - 渡された事実に無いことを推測で補わない。分からないことは「分からない」と why に書く。
    出力は次の JSON オブジェクト1つだけ（前後の文章・コードフェンス禁止）:
    {"verdict": "許可してよい" | "要注意" | "ブロック推奨", "why": "なぜそう言えるかを1〜2文"}
    Rule Scope と Duration は別の仕組みが決めるので、出力に含めない。
    """

    /// モデル出力から JSON を取り出して検査する。
    public static func parseVerdict(_ text: String) -> Result<Verdict, JudgeError> {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b { t = String(t[a...b]) }
        guard let data = t.data(using: .utf8), let v = try? JSONDecoder().decode(Verdict.self, from: data) else {
            return .failure(JudgeError("JSON を読めない: \(String(text.prefix(120)))"))
        }
        guard Verdict.verdicts.contains(v.verdict) else { return .failure(JudgeError("verdict が想定外: \(v.verdict)")) }
        return .success(v)
    }

    /// claude CLI をヘッドレスで呼ぶ。設定・hooks・MCP・プラグイン・スキルを読み込まず、ツールも無効、セッションも残さない。
    /// （--bare は ANTHROPIC_API_KEY 専用で OAuth ログインを読まないため使わない）
    public static func args(prompt: String) -> [String] {
        ["-p", "--model", "haiku",
         "--setting-sources", "",
         "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
         "--disable-slash-commands",
         "--tools", "",
         "--no-session-persistence",
         "--system-prompt", policy,
         "--output-format", "json",
         prompt]
    }

    public static func judge(facts: AlertFacts, investigation: Investigation,
                             claude: String? = findClaude(), timeout: TimeInterval = 30) -> Result<Verdict, JudgeError> {
        guard let claude = claude else {
            return .failure(JudgeError("claude CLI が見つからない（PATH か環境変数 LULU_SIDEKICK_CLAUDE で場所を指定）"))
        }
        let dir = NSTemporaryDirectory() + "lulu-sidekick-judge"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let r = Shell.run(claude, args(prompt: factsText(facts, investigation)), timeout: timeout, cwd: dir)
        if let e = r.launchError { return .failure(JudgeError("claude を起動できない: \(e)")) }
        if r.timedOut { return .failure(JudgeError("\(Int(timeout)) 秒でタイムアウト")) }
        guard r.status == 0 else {
            return .failure(JudgeError("claude が終了コード \(r.status): \(String((r.err + r.out).prefix(200)))"))
        }
        guard let data = r.out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? String else {
            return .failure(JudgeError("claude の出力を読めない: \(String(r.out.prefix(120)))"))
        }
        if (obj["is_error"] as? Bool) == true { return .failure(JudgeError("claude がエラー: \(String(result.prefix(150)))")) }
        return parseVerdict(result)
    }
}

public struct JudgeError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ m: String) { message = m }
    public var description: String { message }
}
