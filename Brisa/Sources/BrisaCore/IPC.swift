import Foundation
import Darwin

public struct IPCRequest: Codable, Sendable {
    public var version: Int
    public var id: String
    public var command: String
    public var arguments: [String]
    public init(command: String, arguments: [String] = [], version: Int = 1, id: String = UUID().uuidString) {
        self.command = command; self.arguments = arguments; self.version = version; self.id = id
    }
    public func validate() throws {
        guard version == 1, UUID(uuidString: id) != nil, command.utf8.count <= 64,
              arguments.count <= 101, arguments.allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }) else {
            throw BrisaError.invalid("Unsupported protocol or invalid request")
        }
    }
}
public struct IPCResponse: Codable, Sendable {
    public var version = 1
    public let id: String
    public let ok: Bool
    public let result: JSONValue?
    public let error: RPCError?
    public init(id: String, result: JSONValue) { self.id = id; ok = true; self.result = result; error = nil }
    public init(id: String, error: Error) {
        self.id = id; ok = false; result = nil
        self.error = RPCError(code: (error as? BrisaError)?.code ?? "internal_error", message: error.localizedDescription)
    }
}
public struct RPCError: Codable, Sendable { public let code: String; public let message: String }

public enum IPCSocket {
    public static let maximumBytes = 8 * 1024 * 1024
    public static var directory: URL {
        // Short per-user path (sockaddr_un is limited to 104 bytes on macOS).
        URL(fileURLWithPath: (try? Paths.systemLocation(NSTemporaryDirectory())) ?? "/nonexistent-brisa-endpoint").appendingPathComponent("dev.brisa.ipc", isDirectory: true)
    }
    public static var path: String { directory.appendingPathComponent("control.sock").path }
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BrisaError.invalid("IPC path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes + Array(repeating: 0, count: $0.count - bytes.count)) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    static func configure(_ fd: Int32, timeout: Int) {
        var noSig: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSig, socklen_t(MemoryLayout.size(ofValue: noSig)))
        var limit = timeval(tv_sec: timeout, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout.size(ofValue: limit)))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout.size(ofValue: limit)))
    }
    static func authenticate(_ fd: Int32) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw BrisaError.rejected("IPC peer is not the current user") }
    }
    static func send<T: Encodable>(_ value: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw BrisaError.invalid("IPC response budget exceeded; narrow your query") }
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw BrisaError.io("IPC send failed or timed out") }; offset += count
            }
        }
    }
    static func receive<T: Decodable>(_ type: T.Type, from fd: Int32, maxBytes: Int = maximumBytes, timeout: TimeInterval = 125) throws -> T {
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            let remaining = timeout - elapsed
            guard remaining > 0 else { throw BrisaError.unavailable("IPC deadline exceeded") }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(Double(Int32.max), ceil(remaining * 1000))))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { throw BrisaError.unavailable("IPC deadline exceeded") }
            let count = Darwin.read(fd, &buffer, min(buffer.count, maxBytes + 1 - data.count))
            if count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard count > 0 else { throw BrisaError.unavailable("App did not respond, connection closed or timed out") }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maxBytes else { throw BrisaError.invalid("IPC frame too large") }
            if let newline = data.firstIndex(of: 10) {
                guard newline == data.count - 1 else { throw BrisaError.invalid("One request per connection") }
                return try JSONDecoder().decode(T.self, from: data.prefix(upTo: newline))
            }
        }
    }
}
public enum IPCClient {
    public static func call(_ request: IPCRequest, path: String = IPCSocket.path, timeout: Int = 120) throws -> IPCResponse {
        try request.validate()
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try SafetyPolicy.rejectSymlinks(parent)
        var st = stat()
        guard lstat(parent, &st) == 0, st.st_uid == getuid(), st.st_mode & 0o077 == 0,
              lstat(path, &st) == 0, st.st_uid == getuid(), st.st_mode & S_IFMT == S_IFSOCK,
              st.st_mode & 0o077 == 0 else { throw BrisaError.rejected("Unsafe IPC endpoint") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrisaError.io("Cannot create socket") }; defer { close(fd) }
        IPCSocket.configure(fd, timeout: timeout)
        var address = try IPCSocket.address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw BrisaError.unavailable("Brisa is not running or its socket is stale") }
        try IPCSocket.authenticate(fd); try IPCSocket.send(request, to: fd)
        let response = try IPCSocket.receive(IPCResponse.self, from: fd, timeout: TimeInterval(timeout))
        guard response.version == 1, response.id == request.id else { throw BrisaError.invalid("Mismatched response") }
        return response
    }
}

public final class IPCServer: @unchecked Sendable {
    private var fd: Int32 = -1
    private var lockFD: Int32 = -1
    private let queue = DispatchQueue(label: "dev.brisa.ipc", qos: .utility)
    private let workers = DispatchQueue(label: "dev.brisa.ipc.connections", qos: .utility, attributes: .concurrent)
    private let connectionSlots = DispatchSemaphore(value: 8)
    private let mutationSlot = DispatchSemaphore(value: 1)
    private var activeClients = Set<Int32>()
    private let lifecycle = NSLock()
    private var stopping = false
    private let path: String
    public init(path: String = IPCSocket.path) { self.path = path }
    public func start(handler: @escaping @Sendable (IPCRequest) -> IPCResponse) throws {
        lifecycle.lock(); defer { lifecycle.unlock() }
        guard fd < 0, lockFD < 0, !stopping else { throw BrisaError.unavailable("IPC server has already started or stopped") }
        var started = false, boundEndpoint = false
        defer {
            if !started {
                if fd >= 0 { close(fd); fd = -1 }
                if boundEndpoint { unlink(path) }
                if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
            }
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try SafetyPolicy.rejectSymlinks(parent.path)
        var st = stat()
        guard lstat(parent.path, &st) == 0, st.st_uid == getuid(), st.st_mode & 0o077 == 0 else { throw BrisaError.rejected("Unsafe IPC directory") }
        lockFD = Darwin.open(parent.appendingPathComponent("server.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw BrisaError.unavailable("Cannot open IPC lock") }
        var lockStat = stat()
        guard fstat(lockFD, &lockStat) == 0, lockStat.st_mode & S_IFMT == S_IFREG,
              lockStat.st_uid == getuid(), lockStat.st_nlink == 1, lockStat.st_mode & 0o077 == 0 else {
            throw BrisaError.rejected("Unsafe IPC lock file")
        }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD); lockFD = -1 }
            throw BrisaError.unavailable("Another Brisa instance owns IPC")
        }
        // Only the lock owner may remove a stale endpoint in the private directory.
        if lstat(path, &st) == 0 {
            guard st.st_mode & S_IFMT == S_IFSOCK, st.st_uid == getuid() else { throw BrisaError.rejected("Unexpected IPC file") }
            unlink(path)
        }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrisaError.io("Cannot create server socket") }
        var address = try IPCSocket.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        boundEndpoint = bound == 0
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { throw BrisaError.io("Cannot bind IPC socket") }
        started = true
        let listeningFD = fd
        queue.async { [weak self] in
            while let self = self {
                self.lifecycle.lock(); let stopped = self.stopping; self.lifecycle.unlock()
                if stopped { break }
                let client = accept(listeningFD, nil, nil)
                if client < 0 { break }
                guard self.connectionSlots.wait(timeout: .now()) == .success else { close(client); continue }
                self.lifecycle.lock()
                if self.stopping {
                    self.lifecycle.unlock(); self.connectionSlots.signal(); close(client); break
                }
                self.activeClients.insert(client)
                self.lifecycle.unlock()
                self.workers.async {
                    defer {
                        self.lifecycle.lock()
                        self.activeClients.remove(client)
                        close(client)
                        self.lifecycle.unlock()
                        self.connectionSlots.signal()
                    }
                    self.serve(client, handler: handler)
                }
            }
        }
    }
    private func serve(_ client: Int32, handler: @Sendable (IPCRequest) -> IPCResponse) {
        IPCSocket.configure(client, timeout: 5)
        var requestID = "invalid"
        do {
            try IPCSocket.authenticate(client)
            let request = try IPCSocket.receive(IPCRequest.self, from: client, maxBytes: 64 * 1024, timeout: 5)
            requestID = request.id
            try request.validate()
            let readOnly: Set<String> = ["status", "categories", "orphans", "worktrees", "diagnostics", "spacemap", "agents", "findings", "journal", "protected",
                "mcp.summary", "mcp.agents", "mcp.large", "mcp.list", "mcp.gitStatus", "mcp.info", "mcp.openFiles", "mcp.git", "mcp.processes"]
            let mutating = !readOnly.contains(request.command)
            if mutating && mutationSlot.wait(timeout: .now()) != .success {
                throw BrisaError.rejected("Another request is awaiting completion in Brisa")
            }
            defer { if mutating { mutationSlot.signal() } }
            IPCSocket.configure(client, timeout: 120)
            try IPCSocket.send(handler(request), to: client)
        } catch { try? IPCSocket.send(IPCResponse(id: requestID, error: error), to: client) }
    }

    public func stop() {
        lifecycle.lock(); defer { lifecycle.unlock() }
        guard !stopping else { return }; stopping = true
        for client in activeClients { shutdown(client, SHUT_RDWR) }
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1; unlink(path) }
        if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
    }
    deinit { stop() }
}
