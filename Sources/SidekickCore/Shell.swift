import Foundation

public struct ShellResult {
    public var status: Int32
    public var out: String
    public var err: String
    public var timedOut: Bool
    public var launchError: String?
}

public enum Shell {
    /// 子プロセスを実行し、stdout/stderr を並行して読む。timeout 秒で terminate する。
    public static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 10,
                           cwd: String? = nil, env: [String: String]? = nil) -> ShellResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd = cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if let env = env { p.environment = env }
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return ShellResult(status: -1, out: "", err: "", timedOut: false, launchError: "\(error)")
        }
        var outData = Data(), errData = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { outData = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { errData = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        var timedOut = false
        let killer = DispatchWorkItem { if p.isRunning { timedOut = true; p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        g.wait()
        return ShellResult(status: p.terminationStatus,
                           out: String(decoding: outData, as: UTF8.self),
                           err: String(decoding: errData, as: UTF8.self),
                           timedOut: timedOut, launchError: nil)
    }
}
