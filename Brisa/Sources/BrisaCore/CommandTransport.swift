import Foundation
import Darwin

/// Structured request for executing an external CLI binary without shell interpolation.
public struct CommandExecutionRequest: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let timeout: TimeInterval
    public let directory: URL?
    public let extraPATHDirectories: [String]
    public let environmentOverrides: [String: String]
    public let maxOutputBytes: Int

    public init(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 15,
        directory: URL? = nil,
        extraPATHDirectories: [String] = [],
        environmentOverrides: [String: String] = [:],
        maxOutputBytes: Int = 2_097_152
    ) {
        self.executable = executable
        self.arguments = arguments
        self.timeout = timeout
        self.directory = directory
        self.extraPATHDirectories = extraPATHDirectories
        self.environmentOverrides = environmentOverrides
        self.maxOutputBytes = maxOutputBytes
    }
}

/// Injectable command transport so adapters use real tools in production and mocks in tests.
public protocol CommandExecuting: Sendable {
    func run(_ request: CommandExecutionRequest, control: ScanControl?) throws -> CommandResult
}

private final class BoundedStreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private(set) var data = Data()
    private(set) var exceeded = false

    init(limit: Int) {
        self.limit = max(1024, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        if data.count + chunk.count > limit {
            exceeded = true
        }
        let remaining = max(0, limit - data.count)
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
    }
}

/// Production command runner executing binaries directly via POSIX `Process` + argv without shells.
public struct LiveCommandExecutor: CommandExecuting {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = Paths.normalized(home)
    }

    public func run(_ request: CommandExecutionRequest, control: ScanControl? = nil) throws -> CommandResult {
        guard request.timeout.isFinite, request.timeout > 0 else {
            throw BrisaError.invalid("Positive finite command timeout required")
        }
        guard request.maxOutputBytes >= 1024, request.maxOutputBytes <= 16_777_216 else {
            throw BrisaError.invalid("Invalid command output limit")
        }
        guard !request.executable.isEmpty,
              !request.executable.contains("\0"),
              request.arguments.allSatisfy({ !$0.contains("\0") }) else {
            throw BrisaError.invalid("Command arguments contain invalid NUL characters")
        }
        guard control?.shouldStop != true else {
            throw BrisaError.unavailable("Operation cancelled or deadline reached")
        }

        try ExecutableLocator.validateExecutable(at: request.executable)

        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: request.executable)
        process.arguments = request.arguments
        process.currentDirectoryURL = request.directory
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let execDir = URL(fileURLWithPath: request.executable).deletingLastPathComponent().path
        let safePath = ExecutableLocator.trustedPATH(
            prioritizing: [execDir] + request.extraPATHDirectories,
            home: home
        )

        var env: [String: String] = [
            "PATH": safePath,
            "HOME": home,
            "LC_ALL": "C",
            "LANG": "C",
            "NO_COLOR": "1",
            "CI": "1",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "COREPACK_ENABLE_DOWNLOAD_PROMPT": "0",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ENV_HINTS": "1",
            "HOMEBREW_NO_COLOR": "1",
            "npm_config_update_notifier": "false",
            "npm_config_fund": "false",
            "npm_config_audit": "false"
        ]
        for (key, value) in request.environmentOverrides where !key.isEmpty && !value.contains("\0") {
            env[key] = value
        }
        process.environment = env

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        out.fileHandleForWriting.closeFile()
        err.fileHandleForWriting.closeFile()

        let group = DispatchGroup()
        let stdout = BoundedStreamBuffer(limit: request.maxOutputBytes)
        let stderr = BoundedStreamBuffer(limit: request.maxOutputBytes)

        for (pipe, buffer) in [(out, stdout), (err, stderr)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let chunk = pipe.fileHandleForReading.readData(ofLength: 16_384)
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                }
                pipe.fileHandleForReading.closeFile()
                group.leave()
            }
        }

        let deadline = min(Date().addingTimeInterval(request.timeout), control?.deadline ?? .distantFuture)
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
                kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 1.0)
            }
        }

        guard group.wait(timeout: .now() + 2.0) == .success else {
            throw BrisaError.unavailable("Subprocess output did not close")
        }
        guard !stdout.exceeded && !stderr.exceeded else {
            throw BrisaError.unavailable("Subprocess output budget exceeded")
        }

        return CommandResult(
            status: process.isRunning ? -1 : process.terminationStatus,
            output: String(decoding: stdout.data, as: UTF8.self),
            error: String(decoding: stderr.data, as: UTF8.self),
            timedOut: timedOut
        )
    }
}

/// Discovers trusted developer tool binaries on macOS without spawning a login shell.
public enum ExecutableLocator {
    private static let fixedSystemDirs = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/Applications/Docker.app/Contents/Resources/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    public static func candidateToolchainDirectories(home: String = NSHomeDirectory(), includeNVM: Bool = true) -> [String] {
        let normalizedHome = Paths.normalized(home)
        var dirs: [String] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/Applications/Docker.app/Contents/Resources/bin",
            normalizedHome + "/Library/pnpm",
            normalizedHome + "/.local/share/pnpm",
            normalizedHome + "/.volta/bin",
            normalizedHome + "/.yarn/bin",
            normalizedHome + "/.config/yarn/global/node_modules/.bin",
            normalizedHome + "/.bun/bin",
            normalizedHome + "/.docker/bin",
            normalizedHome + "/.local/bin"
        ]

        if includeNVM {
            let nvmVersions = normalizedHome + "/.nvm/versions/node"
            if let children = try? FileManager.default.contentsOfDirectory(atPath: nvmVersions) {
                let sorted = children.sorted { compareSemverDescending($0, $1) }
                for version in sorted {
                    dirs.append(nvmVersions + "/" + version + "/bin")
                }
            }
        }

        dirs.append(contentsOf: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
        return deduplicatedSafeDirectories(dirs)
    }

    public static func trustedPATH(prioritizing extra: [String] = [], home: String = NSHomeDirectory()) -> String {
        let combined = extra + candidateToolchainDirectories(home: home) + fixedSystemDirs
        return deduplicatedSafeDirectories(combined).joined(separator: ":")
    }

    public static func resolve(
        name: String,
        extraDirectories: [String] = [],
        home: String = NSHomeDirectory()
    ) -> String? {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\0") else { return nil }
        let searchDirs = deduplicatedSafeDirectories(extraDirectories + candidateToolchainDirectories(home: home))
        for dir in searchDirs {
            let candidate = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(name).path
            if (try? validateExecutable(at: candidate)) != nil {
                return candidate
            }
        }
        return nil
    }

    public static func validateExecutable(at path: String) throws {
        guard !path.isEmpty, path.hasPrefix("/"), !path.contains("\0") else {
            throw BrisaError.invalid("Executable path must be absolute")
        }
        var lst = stat()
        guard lstat(path, &lst) == 0 else {
            throw BrisaError.unavailable("Executable does not exist: \(path)")
        }
        // Resolve symlinks to verify the underlying target is a safe regular executable, not world-writable.
        var st = stat()
        guard stat(path, &st) == 0,
              st.st_mode & S_IFMT == S_IFREG,
              st.st_mode & 0o002 == 0,
              access(path, X_OK) == 0 else {
            throw BrisaError.rejected("Executable fails ownership/permission verification: \(path)")
        }
    }

    private static func deduplicatedSafeDirectories(_ rawDirs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in rawDirs {
            let clean = Paths.normalized(raw)
            guard clean.hasPrefix("/"), clean != ".", !seen.contains(clean) else { continue }
            var st = stat()
            guard stat(clean, &st) == 0,
                  st.st_mode & S_IFMT == S_IFDIR,
                  st.st_mode & 0o002 == 0 else { continue }
            seen.insert(clean)
            result.append(clean)
        }
        return result
    }

    private static func compareSemverDescending(_ lhs: String, _ rhs: String) -> Bool {
        let parse: (String) -> [Int] = { text in
            text.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .compactMap { Int($0) }
        }
        let a = parse(lhs), b = parse(rhs)
        let count = max(a.count, b.count)
        for idx in 0..<count {
            let av = idx < a.count ? a[idx] : 0
            let bv = idx < b.count ? b[idx] : 0
            if av != bv { return av > bv }
        }
        return lhs > rhs
    }
}
