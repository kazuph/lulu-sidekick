import Foundation

/// おすすめの Rule Scope / Duration。AI ではなく、決まりで出す。
public struct Recommendation: Codable, Equatable {
    public var scope: String
    public var duration: String
    /// 判定が「要注意」「ブロック推奨」のとき true。Allow の設定は勧めない。
    public var advisesBlock: Bool

    public var displayLine: String {
        advisesBlock ? "Block（または起動元を確かめてから Once で Allow）"
                     : "Rule Scope: \(scope) ／ Duration: \(duration)"
    }
}

public enum Recommender {
    /// 用途が決まっておらず、どこにでも通信できる汎用コマンド（パスの basename で判定）
    public static func isGenericCommand(_ name: String) -> Bool {
        let n = name.lowercased()
        let exact: Set<String> = ["curl", "wget", "node", "ruby", "perl", "bash", "zsh", "sh", "dash", "fish",
                                  "osascript", "nc", "ncat", "ssh", "scp", "sftp", "git", "rsync", "telnet", "php", "deno", "bun"]
        return exact.contains(n) || n.hasPrefix("python")
    }

    public static func scope(facts: AlertFacts, signature: SignatureInfo?) -> String {
        let name = facts.path.map { ($0 as NSString).lastPathComponent } ?? facts.processName ?? ""
        if isGenericCommand(name) { return "Remote Endpoint" }
        if let s = signature, s.signed, !s.adhoc, s.teamIdentifier != nil || s.isApple { return "Process" }
        return "Remote Endpoint"   // 未署名・ad-hoc・署名を調べられなかった
    }

    /// 行き先がホスト名なら Always、IP だけ（または不明）なら Once
    public static func duration(facts: AlertFacts) -> String {
        guard let h = facts.destHost, !h.isEmpty, !AlertParser.looksLikeIP(h) else { return "Once" }
        return "Always"
    }

    public static func recommend(facts: AlertFacts, signature: SignatureInfo?, verdict: Verdict) -> Recommendation {
        Recommendation(scope: scope(facts: facts, signature: signature), duration: duration(facts: facts),
                       advisesBlock: verdict.verdict != "許可してよい")
    }
}
