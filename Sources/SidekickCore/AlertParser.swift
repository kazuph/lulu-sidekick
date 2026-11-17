import Foundation

public enum AlertParser {
    static let portRegex = try! NSRegularExpression(pattern: #"^\d+ \((TCP|UDP|[A-Za-z]+)\)$"#)
    static let timeRegex = try! NSRegularExpression(pattern: #"^Time stamp:\s*(.+)$"#)

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    public static func looksLikeIP(_ s: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, s, &v4) == 1 || inet_pton(AF_INET6, s, &v6) == 1
    }

    /// static text の値の並びと、text area の値から取り出す。順番には頼らず、パターンで拾う。
    public static func parse(staticTexts: [String], textAreas: [String]) -> AlertFacts {
        var f = AlertFacts()
        let st = staticTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // プロセス名: "Details & Options" の直後。無ければラベルでも値でもない最初の文字列。
        if let i = st.firstIndex(of: "Details & Options"), i + 1 < st.count { f.processName = st[i + 1] }

        let labels: Set<String> = ["Details & Options", "pid:", "args:", "path:", "port/protocol:", "ip address:",
                                   "Connection:", "(reverse) dns:", "Rule Scope:", "Rule Duration:", "Process:", ":"]

        // args: "Process:" の直後（IP やポートの形なら引数なし）
        if let i = st.firstIndex(of: "Process:"), i + 1 < st.count {
            let cand = st[i + 1]
            if !looksLikeIP(cand) && !matches(portRegex, cand) && !cand.hasPrefix("Time stamp:") && !labels.contains(cand) {
                f.args = cand
            }
        }
        for s in st {
            if f.pid == nil, !s.isEmpty, s.allSatisfy({ $0.isNumber }), let n = Int32(s) { f.pid = n; continue }
            if f.port == nil, matches(portRegex, s) { f.port = s; continue }
            if f.ip == nil, looksLikeIP(s) { f.ip = s; continue }
            if f.timestamp == nil, let m = timeRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range(at: 1), in: s) { f.timestamp = String(s[r]) }
        }

        let prefix = "is connecting to "
        for t in textAreas.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !t.isEmpty {
            if t.hasPrefix(prefix) { f.destHost = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
            else if t.hasPrefix("/") && f.path == nil { f.path = t }
            else if f.reverseDNS == nil { f.reverseDNS = t }
        }
        return f
    }
}
