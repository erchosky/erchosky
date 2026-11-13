import XCTest
@testable import BrisaCore

final class ConcurrencyAndCachingRegressionTests: XCTestCase {
    private final class JitteredExecutor: CommandExecuting, @unchecked Sendable {
        func run(_ request: CommandExecutionRequest, control: ScanControl?) throws -> CommandResult {
            let exe = URL(fileURLWithPath: request.executable).lastPathComponent
            let args = request.arguments.joined(separator: " ")

            // Vary sleep durations so parallel adapters finish out of declaration order.
            switch exe {
            case "brew": usleep(45_000)
            case "npm": usleep(15_000)
            case "pnpm": usleep(5_000)
            case "yarn": usleep(25_000)
            case "docker":
                if args.contains("builder du") { usleep(40_000) }
                else if args.contains("system df -v") { usleep(10_000) }
                else if args.contains("volume ls") { usleep(30_000) }
                else { usleep(5_000) }
            default: break
            }

            if exe == "brew" {
                if args == "--version" { return CommandResult(status: 0, output: "Homebrew 4.4.0\n", error: "", timedOut: false) }
                if args == "--cache" { return CommandResult(status: 0, output: "/nonexistent/brew-cache\n", error: "", timedOut: false) }
                return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
            if exe == "npm" {
                if args == "--version" { return CommandResult(status: 0, output: "10.9.0\n", error: "", timedOut: false) }
                if args == "config get cache" { return CommandResult(status: 0, output: "/nonexistent/npm-cache\n", error: "", timedOut: false) }
                return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
            if exe == "pnpm" {
                if args == "--version" { return CommandResult(status: 0, output: "9.12.0\n", error: "", timedOut: false) }
                if args == "store path" { return CommandResult(status: 0, output: "/nonexistent/pnpm-store\n", error: "", timedOut: false) }
                return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
            if exe == "yarn" {
                if args == "--version" { return CommandResult(status: 0, output: "1.22.22\n", error: "", timedOut: false) }
                if args == "cache dir" { return CommandResult(status: 0, output: "/nonexistent/yarn-cache\n", error: "", timedOut: false) }
                return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
            if exe == "docker" {
                if args == "version --format {{.Client.Version}}" { return CommandResult(status: 0, output: "27.3.1\n", error: "", timedOut: false) }
                if args == "info --format {{.ServerVersion}}" { return CommandResult(status: 0, output: "27.3.1\n", error: "", timedOut: false) }
                if args == "system df --format json" {
                    return CommandResult(status: 0, output: "{\"Active\":\"0\",\"Reclaimable\":\"100MB\",\"Size\":\"100MB\",\"TotalCount\":\"1\",\"Type\":\"Images\"}\n", error: "", timedOut: false)
                }
                if args == "system df -v --format json" {
                    let json = """
                    {
                      "Images":[{"ID":"img111","Repository":"alpine","Tag":"3.20","Size":"20MB","SharedSize":"0B","UniqueSize":"20MB","Containers":"1"}],
                      "Containers":[{"ID":"cnt111","Names":"worker","Size":"2MB","State":"exited"}],
                      "Volumes":[{"Name":"vol111","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/vol111/_data","Links":"0","Size":"50MB"}]
                    }
                    """
                    return CommandResult(status: 0, output: json, error: "", timedOut: false)
                }
                if args == "ps -a --format json --no-trunc" {
                    return CommandResult(status: 0, output: "{\"ID\":\"cnt111\",\"Names\":\"worker\",\"Image\":\"alpine:3.20\",\"State\":\"exited\",\"Status\":\"Exited (0)\",\"Size\":\"2MB\",\"Mounts\":\"vol111\",\"CreatedAt\":\"2026-11-10\"}\n", error: "", timedOut: false)
                }
                if request.arguments.first == "inspect" {
                    return CommandResult(status: 0, output: "[{\"Id\":\"cnt111\",\"Name\":\"/worker\",\"Image\":\"sha256:img111\",\"State\":{\"Status\":\"exited\",\"Running\":false},\"Config\":{\"Image\":\"alpine:3.20\"},\"Mounts\":[{\"Type\":\"volume\",\"Name\":\"vol111\"}]}]", error: "", timedOut: false)
                }
                if args == "image ls --format json --no-trunc" {
                    return CommandResult(status: 0, output: "{\"ID\":\"sha256:img111\",\"Repository\":\"alpine\",\"Tag\":\"3.20\",\"Digest\":\"sha256:aaa\",\"CreatedAt\":\"2026-11-01\",\"CreatedSince\":\"10 days\",\"Size\":\"20MB\",\"SharedSize\":\"N/A\",\"UniqueSize\":\"N/A\",\"Containers\":\"1\"}\n", error: "", timedOut: false)
                }
                if args == "volume ls --format json" {
                    return CommandResult(status: 0, output: "{\"Name\":\"vol111\",\"Driver\":\"local\",\"Scope\":\"local\",\"Mountpoint\":\"/var/lib/docker/volumes/vol111/_data\",\"Labels\":\"\",\"Links\":\"N/A\",\"Size\":\"N/A\"}\n", error: "", timedOut: false)
                }
                if args == "builder du --format json" {
                    return CommandResult(status: 0, output: "{\"ID\":\"bc1\",\"Type\":\"regular\",\"Description\":\"build step\",\"Size\":\"30MB\",\"Shared\":false,\"Reclaimable\":true,\"Mutable\":true,\"UsageCount\":1,\"CreatedAt\":\"2026-11-01\",\"LastUsedAt\":\"2026-11-02\",\"Parents\":[]}\n", error: "", timedOut: false)
                }
                return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
            return CommandResult(status: 1, output: "", error: "unknown", timedOut: false)
        }
    }

    private func makeSandbox() throws -> URL {
        let base = try Paths.systemLocation(NSTemporaryDirectory())
        let sandbox = URL(fileURLWithPath: base)
            .appendingPathComponent("BrisaConcurrency-\(UUID().uuidString.prefix(10))", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }

    func testPackageManagerServiceInspectAllPreservesAdapterOrderUnderJitteredConcurrency() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let binDir = sandbox.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        for tool in ["brew", "npm", "pnpm", "yarn"] {
            let exe = binDir.appendingPathComponent(tool)
            try "#!/bin/sh\nexit 0\n".write(to: exe, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        }

        let store = try PrivateStore(directory: sandbox.appendingPathComponent("State"))
        let service = PackageManagerService(
            journal: Journal(store: store),
            home: sandbox.path,
            executor: JitteredExecutor()
        )

        let inspections = service.inspectAll()
        XCTAssertEqual(inspections.map(\.kind), [.homebrew, .npm, .pnpm, .yarn])
        XCTAssertTrue(inspections.allSatisfy(\.isInstalled))
    }

    func testDockerManagerInspectMergesAllResourcesAccuratelyUnderConcurrentQueries() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let dockerExe = sandbox.appendingPathComponent("docker")
        try "#!/bin/sh\nexit 0\n".write(to: dockerExe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dockerExe.path)

        let store = try PrivateStore(directory: sandbox.appendingPathComponent("State"))
        let manager = DockerManager(
            executor: JitteredExecutor(),
            home: sandbox.path,
            journal: Journal(store: store),
            executableOverride: dockerExe.path
        )

        let snap = manager.inspect()
        XCTAssertEqual(snap.status, .ready)
        XCTAssertEqual(snap.containers.count, 1)
        XCTAssertEqual(snap.images.count, 1)
        XCTAssertEqual(snap.volumes.count, 1)
        XCTAssertEqual(snap.buildCacheRecords.count, 1)
        XCTAssertEqual(snap.volumes.first?.protectedByDefault, true)
    }

    func testAppUninstallerPeerCacheInvalidatesWhenPeerBundleChanges() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        func writeBundle(name: String, bundleID: String) throws -> URL {
            let appURL = sandbox.appendingPathComponent("Apps/\(name).app", isDirectory: true)
            let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": bundleID,
                "CFBundleName": name,
                "CFBundleShortVersionString": "1.0"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            return appURL
        }

        let targetA = try writeBundle(name: "TargetA", bundleID: "com.example.targeta")
        let peerB = try writeBundle(name: "PeerB", bundleID: "com.example.peerb")
        let sharedCache = sandbox.appendingPathComponent("Library/Caches/com.example.peerb")
        try FileManager.default.createDirectory(at: sharedCache, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 512).write(to: sharedCache.appendingPathComponent("cache.bin"))

        let store = try PrivateStore(directory: sandbox.appendingPathComponent("State"))
        let uninstaller = AppUninstaller(
            journal: Journal(store: store),
            home: sandbox.path,
            systemRoots: [sandbox.appendingPathComponent("System").path],
            mover: SystemTrashMover()
        )

        let first = uninstaller.inspect(appBundlePath: targetA.path, otherInstalledAppPaths: [targetA.path, peerB.path])
        XCTAssertEqual(first.app.bundleID, "com.example.targeta")

        // Mutate TargetA's Info.plist so its bundle identity updates; reusing cached PeerB must still succeed.
        let updatedTargetAPlist: [String: Any] = [
            "CFBundleIdentifier": "com.example.targeta.v2",
            "CFBundleName": "TargetA",
            "CFBundleShortVersionString": "2.0"
        ]
        let updatedData = try PropertyListSerialization.data(fromPropertyList: updatedTargetAPlist, format: .xml, options: 0)
        try updatedData.write(to: targetA.appendingPathComponent("Contents/Info.plist"))

        let second = uninstaller.inspect(appBundlePath: peerB.path, otherInstalledAppPaths: [targetA.path, peerB.path])
        XCTAssertEqual(second.app.bundleID, "com.example.peerb")
        XCTAssertTrue(second.exclusiveItems.contains(where: { $0.path == sharedCache.path }))
    }
}
