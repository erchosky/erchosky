import XCTest
@testable import BrisaCore

final class PackageManagerAdapterTests: XCTestCase {
    private final class MockCommandExecutor: CommandExecuting, @unchecked Sendable {
        private let lock = NSLock()
        var handler: @Sendable (CommandExecutionRequest, ScanControl?) throws -> CommandResult
        private(set) var recordedRequests: [CommandExecutionRequest] = []

        init(_ handler: @escaping @Sendable (CommandExecutionRequest, ScanControl?) throws -> CommandResult) {
            self.handler = handler
        }

        func run(_ request: CommandExecutionRequest, control: ScanControl?) throws -> CommandResult {
            lock.withLock { recordedRequests.append(request) }
            return try handler(request, control)
        }
    }

    func testHomebrewAdapterInspectsDryRunEstimatesAndExecutesCleanup() throws {
        let f = try Fixture()
        let cacheDir = f.home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 12_288).write(to: cacheDir.appendingPathComponent("foo--1.0.bottle.tar.gz"))

        let executor = MockCommandExecutor { req, _ in
            switch req.arguments {
            case ["--version"]:
                return CommandResult(status: 0, output: "Homebrew 7.0.12\n", error: "", timedOut: false)
            case ["--cache"]:
                return CommandResult(status: 0, output: cacheDir.path + "\n", error: "", timedOut: false)
            case ["cleanup", "--dry-run"]:
                return CommandResult(
                    status: 0,
                    output: "Would remove: \(cacheDir.path)/foo--1.0.bottle.tar.gz (1.5MB)\n==> This operation has freed approximately 1.5MB of disk space.\n",
                    error: "",
                    timedOut: false
                )
            case ["cleanup", "-s", "--dry-run"]:
                return CommandResult(
                    status: 0,
                    output: "Would remove: \(cacheDir.path)/foo--1.0.bottle.tar.gz (1.5MB)\n==> This operation has freed approximately 2.5MB of disk space.\n",
                    error: "",
                    timedOut: false
                )
            case ["cleanup"]:
                try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("foo--1.0.bottle.tar.gz"))
                return CommandResult(status: 0, output: "Removing: \(cacheDir.path)/foo--1.0.bottle.tar.gz...\n", error: "", timedOut: false)
            default:
                return CommandResult(status: 1, output: "", error: "unexpected", timedOut: false)
            }
        }

        let journal = Journal(store: try f.store())
        let readPolicy = ReadAuthorizationPolicy(home: f.home.path, allowSystemLocations: false)
        let adapter = HomebrewAdapter(executor: executor, home: f.home.path, readPolicy: readPolicy, executable: "/opt/homebrew/bin/brew")
        let service = PackageManagerService(journal: journal, home: f.home.path, readPolicy: readPolicy, executor: executor, adapters: [adapter])

        let inspections = service.inspectAll()
        XCTAssertEqual(inspections.count, 1)
        let brew = try XCTUnwrap(inspections.first)
        XCTAssertTrue(brew.isInstalled)
        XCTAssertEqual(brew.versionString, "7.0.12")
        XCTAssertEqual(brew.cachePaths, [Paths.normalized(cacheDir.path)])
        XCTAssertEqual(brew.capabilities.count, 2)

        let stdCap = try XCTUnwrap(brew.capabilities.first { $0.id == "brew.cleanup.standard" })
        XCTAssertEqual(stdCap.scope, .unreferencedAndOutdated)
        XCTAssertEqual(stdCap.estimatedReclaimableBytes, 1_500_000)
        XCTAssertEqual(stdCap.previewedItems.count, 1)

        let plan = service.buildPlan(inspection: brew, capability: stdCap)
        XCTAssertTrue(plan.canExecute)
        XCTAssertEqual(plan.mechanism, .toolCommand)
        XCTAssertEqual(plan.restorability, .irreversible)

        let report = try service.execute(plan: plan, inspection: brew, capability: stdCap)
        XCTAssertEqual(report.outcome, .completed)
        XCTAssertFalse(report.restorable)
        XCTAssertEqual(executor.recordedRequests.last?.arguments, ["cleanup"])

        let jEntry = try XCTUnwrap(try journal.entries().first { $0.id == "plan-\(plan.id)" })
        XCTAssertEqual(jEntry.status, "completed")
        XCTAssertEqual(jEntry.mechanism, "tool_command")
        XCTAssertEqual(jEntry.restorable, false)
    }

    func testNpmVersionDifferencesExposeEntireCacheScopeForModernCAS() throws {
        let f = try Fixture()
        let npmCache = f.home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        try FileManager.default.createDirectory(at: npmCache, withIntermediateDirectories: true)
        try Data(repeating: 0x31, count: 8_192).write(to: npmCache.appendingPathComponent("blob"))

        func runWithVersion(_ version: String) -> PackageManagerInspection {
            let executor = MockCommandExecutor { req, _ in
                switch req.arguments {
                case ["--version"]: return CommandResult(status: 0, output: version + "\n", error: "", timedOut: false)
                case ["config", "get", "cache"]: return CommandResult(status: 0, output: f.home.appendingPathComponent(".npm").path + "\n", error: "", timedOut: false)
                case ["root", "-g"]: return CommandResult(status: 0, output: f.home.appendingPathComponent(".npm-global").path + "\n", error: "", timedOut: false)
                default: return CommandResult(status: 0, output: "", error: "", timedOut: false)
                }
            }
            let adapter = NpmAdapter(executor: executor, home: f.home.path, readPolicy: ReadAuthorizationPolicy(home: f.home.path), executable: "/usr/local/bin/npm")
            return adapter.inspect()
        }

        let modern = runWithVersion("10.9.9")
        XCTAssertEqual(modern.majorVersion, 10)
        XCTAssertEqual(modern.capabilities.map(\.id), ["npm.cache.verify", "npm.cache.clean"])
        let cleanModern = try XCTUnwrap(modern.capabilities.first { $0.id == "npm.cache.clean" })
        XCTAssertEqual(cleanModern.scope, .entireCache)
        XCTAssertEqual(cleanModern.arguments, ["cache", "clean", "--force"])

        let legacy = runWithVersion("4.6.1")
        XCTAssertEqual(legacy.majorVersion, 4)
        XCTAssertEqual(legacy.capabilities.map(\.id), ["npm.cache.clean"])
        XCTAssertEqual(legacy.capabilities.first?.arguments, ["cache", "clean"])
    }

    func testYarnClassicVsBerryCapabilitiesAndCorepackError() throws {
        let f = try Fixture()
        let classicCache = f.home.appendingPathComponent("Library/Caches/Yarn/v6", isDirectory: true)
        let berryGlobal = f.home.appendingPathComponent(".yarn/berry/cache", isDirectory: true)
        try FileManager.default.createDirectory(at: classicCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: berryGlobal, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: classicCache.appendingPathComponent("tarball.tgz"))
        try Data(repeating: 2, count: 4096).write(to: berryGlobal.appendingPathComponent("mirror.zip"))

        let classicExec = MockCommandExecutor { req, _ in
            XCTAssertEqual(req.environmentOverrides["COREPACK_ENABLE_DOWNLOAD_PROMPT"], "0")
            switch req.arguments {
            case ["--version"]: return CommandResult(status: 0, output: "1.22.22\n", error: "", timedOut: false)
            case ["cache", "dir"]: return CommandResult(status: 0, output: classicCache.path + "\n", error: "", timedOut: false)
            default: return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
        }
        let classic = YarnAdapter(executor: classicExec, home: f.home.path, readPolicy: ReadAuthorizationPolicy(home: f.home.path), executable: "/usr/local/bin/yarn").inspect()
        XCTAssertEqual(classic.variantLabel, "Yarn Classic (v1)")
        XCTAssertEqual(classic.capabilities.first?.arguments, ["cache", "clean"])

        let berryExec = MockCommandExecutor { req, _ in
            switch req.arguments {
            case ["--version"]: return CommandResult(status: 0, output: "4.5.0\n", error: "", timedOut: false)
            case ["config", "get", "globalFolder"]: return CommandResult(status: 0, output: f.home.appendingPathComponent(".yarn/berry").path + "\n", error: "", timedOut: false)
            default: return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
        }
        let berry = YarnAdapter(executor: berryExec, home: f.home.path, readPolicy: ReadAuthorizationPolicy(home: f.home.path), executable: "/usr/local/bin/yarn").inspect()
        XCTAssertEqual(berry.variantLabel, "Yarn Berry (v4)")
        XCTAssertEqual(berry.capabilities.first?.arguments, ["cache", "clean", "--mirror"])

        let corepackErrExec = MockCommandExecutor { _, _ in
            CommandResult(status: 1, output: "", error: "Corepack aborted in non-interactive mode", timedOut: false)
        }
        let brokenYarn = YarnAdapter(executor: corepackErrExec, home: f.home.path, readPolicy: ReadAuthorizationPolicy(home: f.home.path), executable: "/usr/local/bin/yarn").inspect()
        XCTAssertTrue(brokenYarn.capabilities.isEmpty)
        XCTAssertEqual(brokenYarn.inspectionError, "Corepack aborted in non-interactive mode")
    }

    func testPnpmStorePruneFailureTimeoutAndCancellationRecordTruthfulJournalOutcomes() throws {
        let f = try Fixture()
        let storePath = f.home.appendingPathComponent("Library/pnpm/store/v11", isDirectory: true)
        try FileManager.default.createDirectory(at: storePath, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: storePath.appendingPathComponent("item.bin"))

        // 1. Failing prune (e.g. active store server)
        let failingExec = MockCommandExecutor { req, _ in
            switch req.arguments {
            case ["--version"]: return CommandResult(status: 0, output: "12.18.0\n", error: "", timedOut: false)
            case ["store", "path"]: return CommandResult(status: 0, output: storePath.path + "\n", error: "", timedOut: false)
            case ["store", "prune"]: return CommandResult(status: 1, output: "", error: "ERR_PNPM_STORE_SERVER_RUNNING", timedOut: false)
            default: return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
        }
        let journal = Journal(store: try f.store())
        let readPolicy = ReadAuthorizationPolicy(home: f.home.path)
        let pnpm = PnpmAdapter(executor: failingExec, home: f.home.path, readPolicy: readPolicy, executable: "/usr/local/bin/pnpm")
        let service = PackageManagerService(journal: journal, home: f.home.path, readPolicy: readPolicy, executor: failingExec, adapters: [pnpm])
        let inspection = try XCTUnwrap(service.inspectAll().first)
        let cap = try XCTUnwrap(inspection.capabilities.first)
        let plan = service.buildPlan(inspection: inspection, capability: cap)

        let failReport = try service.execute(plan: plan, inspection: inspection, capability: cap)
        XCTAssertEqual(failReport.outcome, .failed)
        XCTAssertEqual(failReport.commandOutput, "ERR_PNPM_STORE_SERVER_RUNNING")

        // 2. Cancellation before execution
        let flag = CancellationFlag()
        flag.cancel()
        let plan2 = service.buildPlan(inspection: inspection, capability: cap)
        let cancelReport = try service.execute(plan: plan2, inspection: inspection, capability: cap, cancellation: flag)
        XCTAssertEqual(cancelReport.outcome, .cancelled)

        // 3. Timeout
        let timeoutExec = MockCommandExecutor { req, _ in
            if req.arguments == ["store", "prune"] {
                return CommandResult(status: -1, output: "", error: "", timedOut: true)
            }
            return CommandResult(status: 0, output: "", error: "", timedOut: false)
        }
        let timeoutService = PackageManagerService(journal: journal, home: f.home.path, readPolicy: readPolicy, executor: timeoutExec, adapters: [pnpm])
        let plan3 = timeoutService.buildPlan(inspection: inspection, capability: cap)
        let timeoutReport = try timeoutService.execute(plan: plan3, inspection: inspection, capability: cap)
        XCTAssertEqual(timeoutReport.outcome, .failed)

        let entries = try journal.entries()
        XCTAssertEqual(entries.first { $0.id == "plan-\(plan.id)" }?.status, "failed")
        XCTAssertEqual(entries.first { $0.id == "plan-\(plan2.id)" }?.status, "cancelled")
        XCTAssertEqual(entries.first { $0.id == "plan-\(plan3.id)" }?.status, "failed")
    }
}
