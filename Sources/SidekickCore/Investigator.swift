import Foundation

public enum Investigator {
    static func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }

    /// pid から ppid をたどって launchd まで。取れなかった所は推測せず note に残す。
    public static func parentChain(pid: Int32, processName: String? = nil, maxDepth: Int = 30) -> ParentChain {
        var entries: [ChainEntry] = []
        var cur = pid
        var note: String?
        var seen = Set<Int32>()
        while entries.count < maxDepth {
            if !seen.insert(cur).inserted { note = "連鎖がループした（pid \(cur)）"; break }
            let r = Shell.run("/bin/ps", ["-ww", "-o", "ppid=,command=", "-p", "\(cur)"], timeout: 5)
            let line = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.status != 0 || line.isEmpty {
                note = entries.isEmpty ? "pid \(cur) は終了済みで追えない"
                                       : "pid \(cur)（pid \(entries.last!.pid) の親）は終了済みで追えない"
                break
            }
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let ppid = Int32(parts[0]) else { note = "ps の出力を読めない: \(clip(line, 80))"; break }
            let cmd = String(parts[1])
            // pid 再利用の検査: 最初の1段だけ、通知のプロセス名が含まれなければ別プロセスとみなす
            if entries.isEmpty, let name = processName, !name.isEmpty,
               !cmd.lowercased().contains(name.lowercased()) {
                note = "pid \(cur) は終了済みで追えない（別のプロセス「\(clip(cmd, 40))」に pid が再利用されている）"
                break
            }
            entries.append(ChainEntry(pid: cur, command: clip(cmd, 150)))
            if cur <= 1 || ppid <= 0 { break }
            cur = ppid
        }
        if entries.count >= maxDepth { note = "深さの上限（\(maxDepth)）で打ち切り" }
        return ParentChain(entries: entries, note: note)
    }

    public static func signature(path: String) -> SignatureInfo {
        guard FileManager.default.fileExists(atPath: path) else {
            return SignatureInfo(signed: false, error: "パスが存在しない（削除済みかもしれない）")
        }
        let r = Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", path], timeout: 10)
        if let e = r.launchError { return SignatureInfo(signed: false, error: e) }
        return parseCodesign(r.err, status: r.status)
    }

    public static func parseCodesign(_ text: String, status: Int32) -> SignatureInfo {
        if text.contains("not signed at all") { return SignatureInfo(signed: false, error: "未署名") }
        var sig = SignatureInfo(signed: status == 0)
        if status != 0 { sig.error = clip(text.trimmingCharacters(in: .whitespacesAndNewlines), 200); return sig }
        for line in text.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("Identifier=") { sig.identifier = String(l.dropFirst("Identifier=".count)) }
            else if l.hasPrefix("TeamIdentifier=") {
                let v = String(l.dropFirst("TeamIdentifier=".count)); sig.teamIdentifier = v == "not set" ? nil : v
            } else if l.hasPrefix("Authority=") { sig.authorities.append(String(l.dropFirst("Authority=".count))) }
            else if l.hasPrefix("Signature=adhoc") { sig.adhoc = true }
        }
        sig.isApple = sig.authorities.contains("Software Signing") || sig.authorities.contains("Apple Mac OS Application Signing")
        return sig
    }

    static func normalizeIP(_ s: String) -> String {
        var v4 = in_addr(), v6 = in6_addr()
        var buf = [CChar](repeating: 0, count: 64)
        if inet_pton(AF_INET, s, &v4) == 1 { inet_ntop(AF_INET, &v4, &buf, 64); return String(cString: buf) }
        if inet_pton(AF_INET6, s, &v6) == 1 { inet_ntop(AF_INET6, &v6, &buf, 64); return String(cString: buf) }
        return s.lowercased()
    }

    /// ホスト名の正引き（5秒で打ち切り）。
    public static func resolve(host: String, timeout: TimeInterval = 5) -> (ips: [String], error: String?) {
        var result: (ips: [String], error: String?)?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            let rc = getaddrinfo(host, nil, &hints, &res)
            if rc != 0 { result = ([], "正引き失敗: \(String(cString: gai_strerror(rc)))"); sem.signal(); return }
            var ips: [String] = []
            var p = res
            while let ai = p {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ai.pointee.ai_addr, ai.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = normalizeIP(String(cString: buf)); if !ips.contains(ip) { ips.append(ip) }
                }
                p = ai.pointee.ai_next
            }
            freeaddrinfo(res)
            result = (ips, nil); sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut { return ([], "正引きが \(Int(timeout)) 秒で終わらなかった") }
        return result ?? ([], "正引きの結果なし")
    }

    public static func destination(facts: AlertFacts, resolver: (String) -> (ips: [String], error: String?) = { resolve(host: $0) }) -> DestinationCheck? {
        guard let host = facts.destHost, !host.isEmpty else { return nil }
        let ipOnly = AlertParser.looksLikeIP(host)
        var argsHas: Bool?
        if !ipOnly, let a = facts.args, !a.isEmpty { argsHas = a.lowercased().contains(host.lowercased()) }
        if ipOnly {
            return DestinationCheck(hostIsIPOnly: true, resolvedIPs: [], resolveError: nil, ipMatchesHost: nil, argsContainHost: nil)
        }
        let r = resolver(host)
        var match: Bool?
        if r.error == nil, let ip = facts.ip { match = r.ips.contains(normalizeIP(ip)) }
        return DestinationCheck(hostIsIPOnly: false, resolvedIPs: r.ips, resolveError: r.error, ipMatchesHost: match, argsContainHost: argsHas)
    }
}
