import Foundation

public struct LogEntry: Codable {
    public var time: String
    public var facts: AlertFacts
    public var investigation: Investigation
    public var verdict: Verdict?
    public var recommendation: Recommendation?
    public var judgeError: String?
}

public enum SidekickLog {
    public static var dir: String { NSHomeDirectory() + "/Library/Logs/LuLuSidekick" }

    public static func append(facts: AlertFacts, investigation: Investigation, state: JudgeState, dir: String? = nil) {
        let d = dir ?? Self.dir
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        var e = LogEntry(time: iso.string(from: Date()), facts: facts, investigation: investigation)
        switch state {
        case .done(let v): e.verdict = v; e.recommendation = Recommender.recommend(facts: facts, signature: investigation.signature, verdict: v)
        case .failed(let m): e.judgeError = m
        case .pending: break
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? enc.encode(e) else { return }
        data.append(0x0A)
        let day = String(iso.string(from: Date()).prefix(10))
        let path = d + "/alerts-\(day).jsonl"
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { FileManager.default.createFile(atPath: path, contents: data) }
    }
}
