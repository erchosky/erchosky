import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public let error: String
    public let timedOut: Bool

    public init(status: Int32, output: String, error: String, timedOut: Bool = false) {
        self.status = status
        self.output = output
        self.error = error
        self.timedOut = timedOut
    }
}
private final class Capture: @unchecked Sendable {
    let lock = NSLock()
    var data = Data()
    var exceeded = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        if data.count + chunk.count > 1_048_576 { exceeded = true }
        data.append(chunk.prefix(max(0, 1_048_576 - data.count)))
    }
}
public enum CommandRunner {
    /// Fixed executable and argv only. Never uses a shell or includes provider authentication data.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5,
                           directory: URL? = nil, control: ScanControl? = nil) throws -> CommandResult {
        guard timeout.isFinite, timeout > 0 else { throw BrisaError.invalid("Positive finite command timeout required") }
        guard control?.shouldStop != true else { throw BrisaError.unavailable("Scan cancelled or deadline reached") }
        let process = Process(), out = Pipe(), err = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments; process.currentDirectoryURL = directory
        process.standardOutput = out; process.standardError = err
        process.standardInput = FileHandle.nullDevice
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "LC_ALL": "C", "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"]
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        out.fileHandleForWriting.closeFile(); err.fileHandleForWriting.closeFile()
        let group = DispatchGroup(), stdout = Capture(), stderr = Capture()
        for (pipe, capture) in [(out, stdout), (err, stderr)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let chunk = pipe.fileHandleForReading.readData(ofLength: 16_384)
                    if chunk.isEmpty { break }; capture.append(chunk)
                }
                pipe.fileHandleForReading.closeFile(); group.leave()
            }
        }
        let deadline = min(Date().addingTimeInterval(timeout), control?.deadline ?? .distantFuture)
        var completed = false
        while Date() < deadline, control?.shouldStop != true {
            if done.wait(timeout: .now() + min(0.05, max(0, deadline.timeIntervalSinceNow))) == .success {
                completed = true
                break
            }
        }
        let timedOut = !completed
        if timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 0.3) == .timedOut {
                kill(process.processIdentifier, SIGKILL); _ = done.wait(timeout: .now() + 1)
            }
        }
        guard group.wait(timeout: .now() + 2) == .success else { throw BrisaError.unavailable("Subprocess output did not close") }
        guard !stdout.exceeded && !stderr.exceeded else { throw BrisaError.unavailable("Subprocess output budget exceeded") }
        return CommandResult(status: process.isRunning ? -1 : process.terminationStatus,
            output: String(decoding: stdout.data, as: UTF8.self), error: String(decoding: stderr.data, as: UTF8.self), timedOut: timedOut)
    }
}

/// One lsof query per batch, reused only within the current scan. Unknown results fail closed.
/// Bounded single-path retries isolate a broken path without ignoring lsof warnings.
public final class ScanOpenFileInspector {
    private let paths: [String]
    private let indices: [String: Int]
    private let control: ScanControl
    private let query: ([String], ScanControl) throws -> CommandResult
    private var results: [String: [Int32]] = [:]
    private var failed = Set<String>()
    private var retriesRemaining = 8

    public init(paths: [String], control: ScanControl,
                query: (([String], ScanControl) throws -> CommandResult)? = nil) {
        self.paths = Array(Set(paths)).sorted()
        self.indices = Dictionary(uniqueKeysWithValues: self.paths.enumerated().map { ($0.element, $0.offset) })
        self.control = control
        self.query = query ?? { paths, control in
            try CommandRunner.run("/usr/sbin/lsof", ["-n", "-P", "-Fpn", "--"] + paths, timeout: 5, control: control)
        }
    }

    public func openPIDs(_ path: String) throws -> [Int32] {
        if let result = results[path] { return result }
        guard let index = indices[path], !control.shouldStop else { throw BrisaError.unavailable("Open-file inspection unavailable") }
        if !failed.contains(path) {
            let lower = (index / 64) * 64
            let batch = Array(paths[lower..<min(lower + 64, paths.count)])
            do { results.merge(try inspect(batch)) { _, new in new } }
            catch { failed.formUnion(batch) }
        }
        if let result = results[path] { return result }
        guard retriesRemaining > 0, !control.shouldStop else { throw BrisaError.unavailable("Open-file inspection unavailable") }
        retriesRemaining -= 1
        let isolated = try inspect([path])
        results[path] = isolated[path]
        return results[path] ?? []
    }

    private func inspect(_ batch: [String]) throws -> [String: [Int32]] {
        let r = try query(batch, control)
        guard !r.timedOut, r.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              r.status == 0 || r.status == 1 else { throw BrisaError.unavailable("Cannot establish open-file status") }
        var grouped = Dictionary(uniqueKeysWithValues: batch.map { ($0, [Int32]()) })
        var pid: Int32?
        for line in r.output.split(separator: "\n") {
            if line.first == "p" {
                guard let value = Int32(line.dropFirst()) else { throw BrisaError.invalid("Invalid lsof PID") }
                pid = value
            } else if line.first == "f", pid != nil { continue }
            else if line.first == "n", let pid {
                let name = String(line.dropFirst())
                guard grouped[name] != nil else { throw BrisaError.unavailable("Unrecognized open-file path") }
                grouped[name, default: []].append(pid)
            } else { throw BrisaError.unavailable("Unrecognized open-file output") }
        }
        return grouped.mapValues { Array(Set($0)).sorted() }
    }
}

public struct ProcessInfoEntry: Codable, Identifiable, Sendable {
    public let id: Int32
    public let executable: String
    public let isAgent: Bool
}
public enum ProcessInspector {
    public static func list(control: ScanControl? = nil) throws -> [ProcessInfoEntry] {
        let r = try CommandRunner.run("/bin/ps", ["-U", String(getuid()), "-o", "pid=,comm="], control: control)
        guard r.status == 0, !r.timedOut, r.error.isEmpty else { throw BrisaError.unavailable("Process list unavailable") }
        return r.output.split(separator: "\n").compactMap { line in
            let pair = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard pair.count == 2, let pid = Int32(pair[0]) else { return nil }
            let executable = String(pair[1])
            return ProcessInfoEntry(id: pid, executable: executable,
                isAgent: isAgentExecutable(executable))
        }
    }
    static func isAgentExecutable(_ executable: String) -> Bool {
        let lower = executable.lowercased()
        let name = URL(fileURLWithPath: lower).lastPathComponent
        return AgentDiscovery.executableNames.contains(name) && !lower.contains(".app/")
    }
    public static func openPIDs(_ path: String) throws -> [Int32] {
        let r = try CommandRunner.run("/usr/sbin/lsof", ["-n", "-P", "-t", "--", path], timeout: 5)
        guard !r.timedOut, r.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              r.status == 0 || (r.status == 1 && r.output.isEmpty) else {
            throw BrisaError.rejected("Cannot establish whether this file is open")
        }
        return try r.output.split(separator: "\n").map {
            guard let pid = Int32($0) else { throw BrisaError.rejected("Invalid open-file result") }; return pid
        }
    }
    public static func requireIdle(_ file: IndexedFile) throws {
        try requireIdle(file, processes: list())
    }
    static func requireIdle(_ file: IndexedFile, processes: [ProcessInfoEntry]) throws {
        guard try openPIDs(file.path).isEmpty else { throw BrisaError.rejected("File is open") }
        guard !processes.contains(where: \.isAgent) else {
            throw BrisaError.rejected("A recognized agent session is active; cleanup is paused")
        }
        // Directory access times are unreliable on APFS; use modification times of all parents.
        var parent = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        while SafetyPolicy.within(parent.path, file.root) {
            let values = try parent.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values.contentModificationDate, Date().timeIntervalSince(modified) >= 86400 else {
                throw BrisaError.rejected("Containing directory changed within the last 24 hours")
            }
            if parent.path == file.root { break }; parent.deleteLastPathComponent()
        }
    }
}

public struct GitState: Codable, Sendable {
    public let path: String
    public let dirty: Bool
    public let locked: Bool
    public let detached: Bool
    public let mergedIntoMain: Bool?
    public let removable: Bool
    public let reason: String
}
public enum GitInspector {
    public static func inspect(path: String) throws -> GitState {
        try SafetyPolicy.rejectSymlinks(path)
        func git(_ args: [String]) throws -> String {
            let r = try CommandRunner.run("/usr/bin/git", ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", path] + args)
            guard r.status == 0, !r.timedOut else { throw BrisaError.unavailable("Git inspection failed") }
            return r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let top = try git(["rev-parse", "--show-toplevel"])
        guard top == path else { throw BrisaError.rejected("Not a worktree root") }
        let directory = try git(["rev-parse", "--absolute-git-dir"])
        let dirty = try !git(["status", "--porcelain=v1", "--untracked-files=all"]).isEmpty
        let locked = FileManager.default.fileExists(atPath: directory + "/locked") || FileManager.default.fileExists(atPath: directory + "/index.lock")
        let detached = try git(["rev-parse", "--abbrev-ref", "HEAD"]) == "HEAD"
        return GitState(path: path, dirty: dirty, locked: locked, detached: detached, mergedIntoMain: nil,
                        removable: false, reason: "Inventory only: merge target and session inactivity are not proven. Worktree removal is disabled.")
    }
}

public enum AgentDiscovery {
    static let definitions: [(id: String, name: String, binaries: [String])] = [
        ("codex", "Codex CLI", ["codex"]), ("claude", "Claude Code", ["claude"]),
        ("gemini", "Gemini CLI", ["gemini"]), ("aider", "Aider", ["aider"]),
        ("opencode", "OpenCode", ["opencode"]), ("cursor-agent", "Cursor Agent", ["cursor-agent"]),
        ("copilot", "GitHub Copilot CLI", ["copilot"]), ("antigravity", "Antigravity CLI", ["antigravity", "agy"]),
        ("grok", "Grok CLI", ["grok"]), ("kimi", "Kimi CLI", ["kimi"]), ("qwen", "Qwen Code", ["qwen"])
    ]
    private static let agentPrimaryDirs: [String: [String]] = [
        "claude": [".claude/local"],
        "grok": [".grok/bin"],
        "opencode": [".opencode/bin"]
    ]
    static let executableNames = Set(definitions.flatMap(\.binaries))
    public static func detect() -> [AgentInfo] {
        detect(home: NSHomeDirectory())
    }
    static func detect(home: String, includeSystemLocations: Bool = true) -> [AgentInfo] {
        let normalizedHome = Paths.normalized(home)
        let systemDirs = includeSystemLocations ? ["/opt/homebrew/bin", "/usr/local/bin"] : []
        let sharedUserDirs = [
            "/.npm-global/bin", "/.volta/bin", "/.bun/bin", "/.asdf/shims"
        ].map { normalizedHome + $0 }
            + numericSubdirectories(in: normalizedHome + "/.nvm/versions/node", suffix: "bin")
        return definitions.map { id, name, binaries in
            let directories = searchDirectories(
                for: id,
                home: normalizedHome,
                includeSystemLocations: includeSystemLocations,
                systemDirs: systemDirs,
                sharedUserDirs: sharedUserDirs
            )
            let path = binaries.lazy.compactMap { bin in
                directories.lazy.compactMap { validatedExecutablePath(directory: $0, binary: bin) }.first
            }.first
            return AgentInfo(id: id, name: name, executable: path, authentication: "unknown_not_inspected", executionEnabled: false)
        }
    }

    static func searchDirectories(
        for agentID: String,
        home: String,
        includeSystemLocations: Bool = true
    ) -> [String] {
        let normalizedHome = Paths.normalized(home)
        let systemDirs = includeSystemLocations ? ["/opt/homebrew/bin", "/usr/local/bin"] : []
        let sharedUserDirs = [
            "/.npm-global/bin", "/.volta/bin", "/.bun/bin", "/.asdf/shims"
        ].map { normalizedHome + $0 }
            + numericSubdirectories(in: normalizedHome + "/.nvm/versions/node", suffix: "bin")
        return searchDirectories(
            for: agentID,
            home: normalizedHome,
            includeSystemLocations: includeSystemLocations,
            systemDirs: systemDirs,
            sharedUserDirs: sharedUserDirs
        )
    }

    private static func searchDirectories(
        for agentID: String,
        home: String,
        includeSystemLocations: Bool,
        systemDirs: [String],
        sharedUserDirs: [String]
    ) -> [String] {
        let primaryDirs = (agentPrimaryDirs[agentID] ?? []).map { home + "/" + $0 }
        var fallbackDirs: [String] = []
        if agentID == "codex" {
            if includeSystemLocations {
                fallbackDirs.append("/Applications/Codex.app/Contents/Resources")
            }
            fallbackDirs.append(home + "/Applications/Codex.app/Contents/Resources")
            fallbackDirs += numericSubdirectories(in: home + "/.t3/tools/codex", suffix: "bin")
        }
        return systemDirs + [home + "/.local/bin"] + primaryDirs + sharedUserDirs + fallbackDirs
    }

    /// Reads real subdirectories sorted numerically descending (bounded to avoid huge tool stores).
    private static func numericSubdirectories(in root: String, suffix: String) -> [String] {
        let normalizedRoot = Paths.normalized(root)
        guard let dir = Paths.openDirectory(normalizedRoot) else { return [] }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let entryName = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            guard !entryName.isEmpty, !entryName.hasPrefix("."), !entryName.contains("/") else { continue }
            var st = Darwin.stat()
            let childPath = normalizedRoot + "/" + entryName
            guard lstat(childPath, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
            names.append(entryName)
        }
        return names
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .prefix(50)
            .map { normalizedRoot + "/" + $0 + "/" + suffix }
    }

    /// Rejects directories, special files, traversal segments, and broken symlinks before reporting a CLI binary.
    private static func validatedExecutablePath(directory: String, binary: String) -> String? {
        guard !binary.isEmpty, !binary.contains("/"), binary != ".", binary != ".." else { return nil }
        let normalizedDir = Paths.normalized(directory)
        guard normalizedDir.hasPrefix("/"), !normalizedDir.contains("\0") else { return nil }
        let candidate = Paths.normalized(normalizedDir + "/" + binary)
        guard candidate == (normalizedDir == "/" ? "/" + binary : normalizedDir + "/" + binary) else { return nil }
        var lst = stat()
        guard lstat(candidate, &lst) == 0 else { return nil }
        var st = stat()
        guard stat(candidate, &st) == 0 else { return nil }
        guard (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        guard access(candidate, X_OK) == 0 else { return nil }
        return candidate
    }
}
