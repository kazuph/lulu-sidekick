import Foundation

public enum Summary {
    /// "ruby brew.rb upgrade --cask x" → 実行ファイル名 + 先頭の引数（短く）
    public static func shortLabel(_ command: String, maxLen: Int = 34) -> String {
        var exe = command, rest = ""
        if let r = command.range(of: #"^/.*?\.app/Contents/MacOS/[^ ]+"#, options: .regularExpression) {
            exe = String(command[r]); rest = String(command[r.upperBound...])
        } else if let sp = command.firstIndex(of: " ") {
            exe = String(command[..<sp]); rest = String(command[sp...])
        }
        let base = (exe as NSString).lastPathComponent
        let args = rest.split(separator: " ").filter { !$0.hasPrefix("-") }.prefix(3).map { (a: Substring) -> String in a.hasPrefix("/") ? (String(a) as NSString).lastPathComponent : String(a) }
        var s = ([base] + args).joined(separator: " ")
        if s.count > maxLen { s = String(s.prefix(maxLen - 1)) + "…" }
        return s
    }

    /// 親の連鎖を「祖先 → … → 通知のプロセス」の順で短く。
    public static func chainLine(_ chain: ParentChain, maxEntries: Int = 6) -> String {
        if chain.entries.isEmpty { return chain.note ?? "追えない" }
        var labels = chain.entries.reversed().map { shortLabel($0.command) }
        if labels.count > maxEntries { labels = ["…"] + labels.suffix(maxEntries) }
        var s = labels.joined(separator: " → ")
        if let n = chain.note { s += "\n（\(n)）" }
        return s
    }

    /// 通知のプロセスの引数とコマンドから URL を全部抜き出す（重複は除く・順番は出てきた順）。
    /// パネルでは切らずに出す。伏せ字にした後の文字列を渡すこと。
    public static func urls(_ f: AlertFacts, _ chain: ParentChain?) -> [String] {
        let sources = [f.args, chain?.entries.first?.command].compactMap { $0 }
        var out: [String] = []
        for s in sources {
            for m in urlRegex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                guard let r = Range(m.range, in: s) else { continue }
                var u = String(s[r])
                while let last = u.last, ".,;:)]}>'\"".contains(last) { u.removeLast() }
                if !out.contains(u) { out.append(u) }
            }
        }
        return out
    }

    static let urlRegex = try! NSRegularExpression(pattern: #"(?i)\b[a-z][a-z0-9+.-]*://[^\s'"<>]+"#)

    public static func destinationLine(_ f: AlertFacts, _ d: DestinationCheck?) -> String {
        let host = f.destHost ?? "不明"
        var s = host
        if let ip = f.ip, ip != host { s += "  \(ip)" }
        if let p = f.port { s += "  \(p)" }
        guard let d = d else { return s }
        if d.hostIsIPOnly { s += "\n正引き照合: できない（IPのみ）"; return s }
        if let e = d.resolveError { s += "\n正引き: \(e)" }
        else if let m = d.ipMatchesHost { s += "\n正引き一致: \(m ? "あり" : "なし（IPが別）")" }
        if let a = d.argsContainHost { s += " / 引数に行き先: \(a ? "あり" : "なし")" }
        return s
    }
}
