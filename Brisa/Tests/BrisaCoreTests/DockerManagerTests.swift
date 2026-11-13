import XCTest
@testable import BrisaCore

final class DockerManagerTests: XCTestCase {
    private final class MockDockerExecutor: CommandExecuting, @unchecked Sendable {
        private let lock = NSLock()
        private let handler: @Sendable (CommandExecutionRequest, ScanControl?) throws -> CommandResult
        private(set) var recordedArguments: [[String]] = []

        init(_ handler: @escaping @Sendable (CommandExecutionRequest, ScanControl?) throws -> CommandResult) {
            self.handler = handler
        }

        func run(_ request: CommandExecutionRequest, control: ScanControl?) throws -> CommandResult {
            lock.withLock { recordedArguments.append(request.arguments) }
            return try handler(request, control)
        }
    }

    private final class RecheckCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func next() -> Int {
            lock.withLock {
                count += 1
                return count
            }
        }
    }

    private func sampleSnapshotExecutor(
        runningContainerStartedOnRecheck: Bool = false,
        failOnSecondRemove: Bool = false
    ) -> MockDockerExecutor {
        let recheckCounter = RecheckCounter()

        return MockDockerExecutor { req, control in
            let args = req.arguments
            if args == ["version", "--format", "{{.Client.Version}}"] {
                return CommandResult(status: 0, output: "29.9.2\n", error: "", timedOut: false)
            }
            if args == ["info", "--format", "{{json .ServerVersion}}"] {
                return CommandResult(status: 0, output: "\"29.5.2\"\n", error: "", timedOut: false)
            }
            if args == ["system", "df", "--format", "json"] {
                let ndjson = """
                {"Active":"1","Reclaimable":"1.2GB (60%)","Size":"2.0GB","TotalCount":"2","Type":"Images"}
                {"Active":"1","Reclaimable":"10MB (50%)","Size":"20MB","TotalCount":"2","Type":"Containers"}
                {"Active":"1","Reclaimable":"500MB (50%)","Size":"1.0GB","TotalCount":"2","Type":"Local Volumes"}
                {"Active":"0","Reclaimable":"250MB","Size":"250MB","TotalCount":"2","Type":"Build Cache"}
                """
                return CommandResult(status: 0, output: ndjson, error: "", timedOut: false)
            }
            if args == ["system", "df", "-v", "--format", "json"] {
                let json = """
                {
                  "Images": [
                    {"ID":"111111111111","Repository":"postgres","Tag":"16","Size":"800MB","SharedSize":"200MB","UniqueSize":"600MB","Containers":"1"},
                    {"ID":"222222222222","Repository":"old-app","Tag":"dev","Size":"1.4GB","SharedSize":"200MB","UniqueSize":"1.2GB","Containers":"1"}
                  ],
                  "Containers": [
                    {"ID":"aaaa1111aaaa","Names":"pg-live","Size":"10MB","State":"running"},
                    {"ID":"bbbb2222bbbb","Names":"old-job","Size":"10MB","State":"exited"}
                  ],
                  "Volumes": [
                    {"Name":"pg-data","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/pg-data/_data","Links":"1","Size":"500MB"},
                    {"Name":"orphan-cache","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/orphan-cache/_data","Links":"0","Size":"500MB"}
                  ]
                }
                """
                return CommandResult(status: 0, output: json, error: "", timedOut: false)
            }
            if args == ["ps", "-a", "--format", "json", "--no-trunc"] {
                let ndjson = """
                {"ID":"aaaa1111aaaa0000","Names":"pg-live","Image":"postgres:16","State":"running","Status":"Up 2 hours","Size":"10MB (virtual 800MB)","Mounts":"pg-data","CreatedAt":"2026-11-10"}
                {"ID":"bbbb2222bbbb0000","Names":"old-job","Image":"old-app:dev","State":"exited","Status":"Exited (0) 3 days ago","Size":"10MB (virtual 1.4GB)","Mounts":"orphan-cache","CreatedAt":"2026-11-08"}
                """
                return CommandResult(status: 0, output: ndjson, error: "", timedOut: false)
            }
            if args.first == "inspect" && args.contains("--format") && args.contains("json") {
                let json = """
                [
                  {"Id":"aaaa1111aaaa0000","Name":"/pg-live","Image":"sha256:111111111111","State":{"Status":"running","Running":true},"Config":{"Image":"postgres:16"},"Mounts":[{"Type":"volume","Name":"pg-data"}]},
                  {"Id":"bbbb2222bbbb0000","Name":"/old-job","Image":"sha256:222222222222","State":{"Status":"exited","Running":false},"Config":{"Image":"old-app:dev"},"Mounts":[{"Type":"volume","Name":"orphan-cache"}]}
                ]
                """
                return CommandResult(status: 0, output: json, error: "", timedOut: false)
            }
            if args == ["image", "ls", "--format", "json", "--no-trunc"] {
                let ndjson = """
                {"ID":"sha256:1111111111110000","Repository":"postgres","Tag":"16","Digest":"sha256:aaa","CreatedAt":"2026-11-01","CreatedSince":"12 days ago","Size":"800MB","SharedSize":"N/A","UniqueSize":"N/A","Containers":"1"}
                {"ID":"sha256:2222222222220000","Repository":"old-app","Tag":"dev","Digest":"<none>","CreatedAt":"2026-11-02","CreatedSince":"11 days ago","Size":"1.4GB","SharedSize":"N/A","UniqueSize":"N/A","Containers":"1"}
                """
                return CommandResult(status: 0, output: ndjson, error: "", timedOut: false)
            }
            if args == ["volume", "ls", "--format", "json"] {
                let ndjson = """
                {"Name":"pg-data","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/pg-data/_data","Labels":"","Links":"N/A","Size":"N/A"}
                {"Name":"orphan-cache","Driver":"local","Scope":"local","Mountpoint":"/var/lib/docker/volumes/orphan-cache/_data","Labels":"","Links":"N/A","Size":"N/A"}
                """
                return CommandResult(status: 0, output: ndjson, error: "", timedOut: false)
            }
            if args == ["builder", "du", "--format", "json"] {
                let ndjson = """
                {"ID":"bc1","Type":"regular","Description":"cargo build","Size":"150MB","Shared":true,"Reclaimable":true,"Mutable":true,"UsageCount":2,"CreatedAt":"2026-11-01","LastUsedAt":"2026-11-05","Parents":[]}
                {"ID":"bc2","Type":"source.local","Description":"context","Size":"100MB","Shared":false,"Reclaimable":true,"Mutable":true,"UsageCount":1,"CreatedAt":"2026-11-02","LastUsedAt":"2026-11-05","Parents":[]}
                """
                return CommandResult(status: 0, output: ndjson, error: "", timedOut: false)
            }
            if args == ["inspect", "--format", "{{.State.Running}}", "bbbb2222bbbb0000"] {
                let started = runningContainerStartedOnRecheck && recheckCounter.next() > 0
                return CommandResult(status: 0, output: started ? "true\n" : "false\n", error: "", timedOut: false)
            }
            if args.starts(with: ["ps", "-a", "--filter"]) {
                return CommandResult(status: 0, output: "", error: "", timedOut: false)
            }
            if args == ["rm", "bbbb2222bbbb0000"] {
                return CommandResult(status: 0, output: "bbbb2222bbbb0000\n", error: "", timedOut: false)
            }
            if args == ["rmi", "sha256:2222222222220000"] {
                if failOnSecondRemove {
                    return CommandResult(status: 1, output: "", error: "conflict: unable to remove image", timedOut: false)
                }
                control?.cancellation.cancel()
                return CommandResult(status: 0, output: "Deleted: sha256:2222222222220000\n", error: "", timedOut: false)
            }
            if args == ["volume", "rm", "orphan-cache"] {
                return CommandResult(status: 0, output: "orphan-cache\n", error: "", timedOut: false)
            }
            if args == ["builder", "prune", "--force"] {
                return CommandResult(status: 0, output: "Total reclaimed space: 250MB\n", error: "", timedOut: false)
            }
            return CommandResult(status: 1, output: "", error: "unexpected args: \(args)", timedOut: false)
        }
    }

    private func makeJournal(home: URL) throws -> Journal {
        let store = try PrivateStore(directory: home.appendingPathComponent("Library/Application Support/Brisa", isDirectory: true))
        return Journal(store: store)
    }

    func testInspectSeparatesDaemonUnavailableFromMissingCLI() throws {
        let f = try Fixture()

        let missingCLI = DockerManager(
            executor: MockDockerExecutor { _, _ in CommandResult(status: 0, output: "", error: "", timedOut: false) },
            home: f.home.path,
            executableOverride: ""
        )
        let missingSnapshot = missingCLI.inspect()
        XCTAssertEqual(missingSnapshot.status, .cliUnavailable)
        XCTAssertNil(missingSnapshot.executablePath)

        let stoppedEngine = DockerManager(
            executor: MockDockerExecutor { req, _ in
                if req.arguments == ["version", "--format", "{{.Client.Version}}"] {
                    return CommandResult(status: 0, output: "29.9.2\n", error: "", timedOut: false)
                }
                return CommandResult(
                    status: 1,
                    output: "",
                    error: "Cannot connect to the Docker daemon at unix:///Users/test/.colima/default/docker.sock. Is the docker daemon running?",
                    timedOut: false
                )
            },
            home: f.home.path,
            executableOverride: "/usr/local/bin/docker"
        )
        let stoppedSnapshot = stoppedEngine.inspect()
        XCTAssertEqual(stoppedSnapshot.status, .daemonUnavailable)
        XCTAssertEqual(stoppedSnapshot.clientVersion, "29.9.2")
        XCTAssertNil(stoppedSnapshot.serverVersion)
    }

    func testInspectMergesSharedUniqueSizesAndContainerDependencies() throws {
        let f = try Fixture()
        let manager = DockerManager(
            executor: sampleSnapshotExecutor(),
            home: f.home.path,
            executableOverride: "/usr/local/bin/docker"
        )

        let snapshot = manager.inspect()
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.clientVersion, "29.9.2")
        XCTAssertEqual(snapshot.serverVersion, "29.5.2")
        XCTAssertEqual(snapshot.runningContainers.count, 1)
        XCTAssertEqual(snapshot.stoppedContainers.count, 1)
        XCTAssertEqual(snapshot.buildCacheRecords.count, 2)

        let postgresImage = try XCTUnwrap(snapshot.images.first(where: { $0.repository == "postgres" }))
        XCTAssertEqual(postgresImage.sharedBytes, 200_000_000)
        XCTAssertEqual(postgresImage.uniqueBytes, 600_000_000)
        XCTAssertTrue(postgresImage.isUsedByRunningContainer)
        XCTAssertEqual(postgresImage.referencingContainerNames, ["pg-live"])

        let pgVolume = try XCTUnwrap(snapshot.volumes.first(where: { $0.name == "pg-data" }))
        XCTAssertEqual(pgVolume.sizeBytes, 500_000_000)
        XCTAssertTrue(pgVolume.isMountedByRunningContainer)
        XCTAssertTrue(pgVolume.protectedByDefault)
    }

    func testPlanBlocksRunningResourcesDependenciesAndLockedVolumes() throws {
        let f = try Fixture()
        let manager = DockerManager(
            executor: sampleSnapshotExecutor(),
            home: f.home.path,
            executableOverride: "/usr/local/bin/docker"
        )
        let snapshot = manager.inspect()

        let blockedPlan = manager.buildPlan(
            snapshot: snapshot,
            selection: DockerCleanupSelection(
                containerIDs: ["aaaa1111aaaa0000"],
                imageIDs: ["sha256:1111111111110000", "sha256:2222222222220000"],
                volumeNames: ["orphan-cache"],
                unlockedVolumeNames: []
            )
        )
        XCTAssertFalse(blockedPlan.canExecute)
        XCTAssertEqual(blockedPlan.restorability, .irreversible)
        XCTAssertEqual(blockedPlan.mechanism, .toolCommand)
        XCTAssertEqual(blockedPlan.sizeBasis, .estimated)
        let ids = blockedPlan.blockers.map(\.id)
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("running_container:") }))
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("image_used_by_running_container:") }))
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("image_used_by_stopped_container:") }))
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("volume_locked_by_default:") }))
        XCTAssertTrue(ids.contains(where: { $0.hasPrefix("volume_mounted_by_stopped_container:") }))

        let validPlan = manager.buildPlan(
            snapshot: snapshot,
            selection: DockerCleanupSelection(
                containerIDs: ["bbbb2222bbbb0000"],
                imageIDs: ["sha256:2222222222220000"],
                volumeNames: ["orphan-cache"],
                unlockedVolumeNames: ["orphan-cache"],
                buildCacheScope: .reclaimableOnly
            )
        )
        XCTAssertTrue(validPlan.canExecute, "Unexpected blockers: \(validPlan.blockers.map(\.id))")
        XCTAssertTrue(validPlan.requiresExplicitVolumeUnlock)
    }

    func testExecuteOrdersContainersBeforeImagesAndRecordsCancellationWithoutRollback() throws {
        let f = try Fixture()
        let executor = sampleSnapshotExecutor()
        let journal = try makeJournal(home: f.home)
        let manager = DockerManager(
            executor: executor,
            home: f.home.path,
            journal: journal,
            executableOverride: "/usr/local/bin/docker"
        )
        let snapshot = manager.inspect()

        let selection = DockerCleanupSelection(
            containerIDs: ["bbbb2222bbbb0000"],
            imageIDs: ["sha256:2222222222220000"],
            volumeNames: ["orphan-cache"],
            unlockedVolumeNames: ["orphan-cache"],
            buildCacheScope: .reclaimableOnly
        )
        let plan = manager.buildPlan(snapshot: snapshot, selection: selection)
        XCTAssertTrue(plan.canExecute)

        let control = ScanControl()
        let result = try manager.execute(plan: plan, selection: selection, control: control)
        XCTAssertEqual(result.removedContainerIDs, ["bbbb2222bbbb0000"])
        XCTAssertEqual(result.removedImageIDs, ["sha256:2222222222220000"])
        XCTAssertTrue(result.removedVolumeNames.isEmpty)
        XCTAssertNil(result.prunedBuildCacheScope)
        XCTAssertEqual(result.report.outcome, .cancelled)
        XCTAssertEqual(result.report.completedItems.count, 2)
        XCTAssertEqual(result.report.restorable, false)

        let entries = try journal.entries()
        XCTAssertTrue(entries.contains(where: {
            $0.outcomeKind == "cancelled"
                && $0.domain == "docker"
                && $0.mechanism == "tool_command"
                && $0.restorable == false
                && $0.completedCount == 2
                && ($0.detailNote ?? "").contains("cancelled_no_rollback")
        }))

        let rmIdx = executor.recordedArguments.firstIndex(of: ["rm", "bbbb2222bbbb0000"])
        let rmiIdx = executor.recordedArguments.firstIndex(of: ["rmi", "sha256:2222222222220000"])
        XCTAssertNotNil(rmIdx)
        XCTAssertNotNil(rmiIdx)
        XCTAssertLessThan(rmIdx!, rmiIdx!)
        XCTAssertFalse(executor.recordedArguments.contains(where: { $0.prefix(2) == ["system", "prune"] }))
    }

    func testExecuteRevalidatesBeforeRemovalAndReportsPartialFailure() throws {
        let f = try Fixture()
        let executor = sampleSnapshotExecutor(
            runningContainerStartedOnRecheck: false,
            failOnSecondRemove: true
        )
        let journal = try makeJournal(home: f.home)
        let manager = DockerManager(
            executor: executor,
            home: f.home.path,
            journal: journal,
            executableOverride: "/usr/local/bin/docker"
        )
        let snapshot = manager.inspect()

        let selection = DockerCleanupSelection(
            containerIDs: ["bbbb2222bbbb0000"],
            imageIDs: ["sha256:2222222222220000"]
        )
        let plan = manager.buildPlan(snapshot: snapshot, selection: selection)
        let result = try manager.execute(plan: plan, selection: selection)

        XCTAssertEqual(result.removedContainerIDs, ["bbbb2222bbbb0000"])
        XCTAssertTrue(result.removedImageIDs.isEmpty)
        XCTAssertEqual(result.report.outcome, .partial)
        XCTAssertEqual(result.report.completedItems.count, 1)
        XCTAssertEqual(result.report.failedItems.count, 1)

        let startedExecutor = sampleSnapshotExecutor(runningContainerStartedOnRecheck: true)
        let startedManager = DockerManager(
            executor: startedExecutor,
            home: f.home.path,
            journal: journal,
            executableOverride: "/usr/local/bin/docker"
        )
        let rejectedResult = try startedManager.execute(
            plan: plan,
            selection: DockerCleanupSelection(containerIDs: ["bbbb2222bbbb0000"])
        )
        XCTAssertTrue(rejectedResult.removedContainerIDs.isEmpty)
        XCTAssertEqual(rejectedResult.report.outcome, .rejected)
        XCTAssertFalse(startedExecutor.recordedArguments.contains(["rm", "bbbb2222bbbb0000"]))
    }

    func testReadOnlyLiveDockerInspectIfInstalledDoesNotMutate() throws {
        guard ExecutableLocator.resolve(name: "docker") != nil else { return }
        let f = try Fixture()
        let manager = DockerManager(home: f.home.path)
        let snapshot = manager.inspect()
        XCTAssertNotNil(snapshot.executablePath)
        XCTAssertTrue([.ready, .daemonUnavailable, .permissionDenied].contains(snapshot.status))
    }
}
