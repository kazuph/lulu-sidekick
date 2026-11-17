import Foundation

/// 引数やコマンドに入っている秘密（トークン・パスワード・API キー・Cookie）を伏せ字にする。
/// AI に送る前・パネルに出す前・ログに書く前に通す。行き先のホスト名は残す。
public enum Redactor {
    public static let mask = "[伏せ字]"

    /// (正規表現, 置き換え)。置き換えの $1 などで、伏せない前半を残す。
    static let rules: [(NSRegularExpression, String)] = {
        let defs: [(String, String)] = [
            // URL の中の user:password@
            (#"(://[^/\s:@]+):[^/\s@]+@"#, "$1:\(mask)@"),
            // curl -u user:password / --user user:password
            (#"((?:^|\s)(?:-u|--user|--proxy-user)\s+[^\s:]+):\S+"#, "$1:\(mask)"),
            // Authorization: Bearer xxx / Basic xxx / token xxx（ヘッダーの値）
            (#"(?i)((?:proxy-)?authorization\s*:\s*(?:bearer|basic|token|digest)?\s*)\S+"#, "$1\(mask)"),
            // Cookie: a=b; c=d（次のオプションまで）
            (#"(?i)((?:^|\s)(?:cookie|set-cookie)\s*:\s*).+?(?=\s-{1,2}[A-Za-z]|$)"#, "$1\(mask)"),
            // X-Api-Key: xxx / X-Auth-Token: xxx など
            (#"(?i)(x-[a-z-]*(?:key|token|secret|auth)[a-z-]*\s*:\s*)\S+"#, "$1\(mask)"),
            // key=value / --key value / ?key=value&（名前に秘密らしい語を含むもの）
            (#"(?i)((?:^|[\s?&;,"'])-{0,2}[a-z_-]*(?:api[_-]?key|access[_-]?key|secret|token|password|passwd|pwd|credential)[a-z_-]*(?:\s*[=:]\s*|\s+))[^\s&"',;]+"#, "$1\(mask)"),
            // よく知られた形のトークン
            (#"\bgh[pousr]_[A-Za-z0-9]{20,}"#, mask),
            (#"\bgithub_pat_[A-Za-z0-9_]{20,}"#, mask),
            (#"\bsk-[A-Za-z0-9_-]{20,}"#, mask),
            (#"\bxox[abprs]-[A-Za-z0-9-]{10,}"#, mask),
            (#"\bAKIA[0-9A-Z]{16}\b"#, mask),
            (#"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, mask),
        ]
        return defs.map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
    }()

    public static func redact(_ s: String) -> String {
        var out = s
        for (re, tpl) in rules {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: tpl)
        }
        return out
    }

    public static func redact(_ f: AlertFacts) -> AlertFacts {
        var r = f
        r.args = f.args.map(redact)
        return r
    }

    public static func redact(_ c: ParentChain) -> ParentChain {
        ParentChain(entries: c.entries.map { ChainEntry(pid: $0.pid, command: redact($0.command)) }, note: c.note)
    }
}
