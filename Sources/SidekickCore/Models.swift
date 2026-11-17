import Foundation

/// LuLu の通知ウィンドウから読み取った値。
public struct AlertFacts: Codable, Equatable {
    public var processName: String?
    public var pid: Int32?
    public var path: String?
    public var args: String?
    public var destHost: String?
    public var ip: String?
    public var port: String?          // 例: "443 (TCP)"
    public var reverseDNS: String?
    public var timestamp: String?     // 例: "12:07:13"

    public init(processName: String? = nil, pid: Int32? = nil, path: String? = nil, args: String? = nil,
                destHost: String? = nil, ip: String? = nil, port: String? = nil,
                reverseDNS: String? = nil, timestamp: String? = nil) {
        self.processName = processName; self.pid = pid; self.path = path; self.args = args
        self.destHost = destHost; self.ip = ip; self.port = port
        self.reverseDNS = reverseDNS; self.timestamp = timestamp
    }

    /// 通知の識別キー（pid + Time stamp）。どちらかが欠けていれば nil。
    public var key: String? {
        guard let pid = pid, let ts = timestamp else { return nil }
        return "\(pid)@\(ts)"
    }
}

public struct ChainEntry: Codable, Equatable {
    public var pid: Int32
    public var command: String
    public init(pid: Int32, command: String) { self.pid = pid; self.command = command }
}

/// 親プロセスの連鎖。entries[0] が通知のプロセス、最後が launchd 側。
public struct ParentChain: Codable, Equatable {
    public var entries: [ChainEntry]
    public var note: String?
    public init(entries: [ChainEntry], note: String? = nil) { self.entries = entries; self.note = note }
}

public struct SignatureInfo: Codable, Equatable {
    public var signed: Bool
    public var identifier: String?
    public var teamIdentifier: String?
    public var authorities: [String]
    public var adhoc: Bool
    public var isApple: Bool
    public var error: String?
    public init(signed: Bool, identifier: String? = nil, teamIdentifier: String? = nil, authorities: [String] = [],
                adhoc: Bool = false, isApple: Bool = false, error: String? = nil) {
        self.signed = signed; self.identifier = identifier; self.teamIdentifier = teamIdentifier
        self.authorities = authorities; self.adhoc = adhoc; self.isApple = isApple; self.error = error
    }
}

public struct DestinationCheck: Codable, Equatable {
    public var hostIsIPOnly: Bool
    public var resolvedIPs: [String]
    public var resolveError: String?
    /// 正引き結果に通知の IP が含まれるか。ホストが IP のみ・正引き失敗なら nil。
    public var ipMatchesHost: Bool?
    /// 引数の中に行き先ホストが出てくるか。引数が無い・ホストが IP のみなら nil。
    public var argsContainHost: Bool?
    public init(hostIsIPOnly: Bool, resolvedIPs: [String], resolveError: String?, ipMatchesHost: Bool?, argsContainHost: Bool?) {
        self.hostIsIPOnly = hostIsIPOnly; self.resolvedIPs = resolvedIPs; self.resolveError = resolveError
        self.ipMatchesHost = ipMatchesHost; self.argsContainHost = argsContainHost
    }
}

public struct Investigation: Codable, Equatable {
    public var chain: ParentChain
    public var signature: SignatureInfo?
    public var destination: DestinationCheck?
    public init(chain: ParentChain, signature: SignatureInfo? = nil, destination: DestinationCheck? = nil) {
        self.chain = chain; self.signature = signature; self.destination = destination
    }
}

public struct Verdict: Codable, Equatable {
    public var verdict: String
    public var why: String
    public init(verdict: String, why: String) { self.verdict = verdict; self.why = why }
    public static let verdicts = ["許可してよい", "要注意", "ブロック推奨"]
}

public enum JudgeState: Equatable {
    case pending
    case done(Verdict)
    case failed(String)
}
