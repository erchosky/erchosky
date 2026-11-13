import XCTest
@testable import BrisaCore

final class LocalizationAndTelemetryTests: XCTestCase {
    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - Modular Localization & Preferences

    func testAppLanguageSanitizeAndResolve() {
        XCTAssertEqual(AppLanguage.sanitizedPreference(nil), "system")
        XCTAssertEqual(AppLanguage.sanitizedPreference(""), "system")
        XCTAssertEqual(AppLanguage.sanitizedPreference("ES"), "es")
        XCTAssertEqual(AppLanguage.sanitizedPreference(" en "), "en")
        XCTAssertEqual(AppLanguage.sanitizedPreference("fr"), "system")

        XCTAssertEqual(AppLanguage.resolve(preference: "es", preferredLanguages: ["en-US"]), .es)
        XCTAssertEqual(AppLanguage.resolve(preference: "en", preferredLanguages: ["es-ES"]), .en)
        XCTAssertEqual(AppLanguage.resolve(preference: "system", preferredLanguages: ["es-419", "en-US"]), .es)
        XCTAssertEqual(AppLanguage.resolve(preference: "system", preferredLanguages: ["en_GB", "es-ES"]), .en)
        XCTAssertEqual(
            AppLanguage.resolve(preference: "system", preferredLanguages: ["fr-FR", "ja-JP"]),
            AppLanguage.fallbackLanguage
        )
        XCTAssertEqual(
            AppLanguage.system.concreteCode(preferredLanguages: ["es-MX"]),
            "es"
        )
        XCTAssertEqual(AppLanguage.es.nativeName, "Español")
        XCTAssertEqual(AppLanguage.en.nativeName, "English")
    }

    func testLocalizationTablesHaveCompleteBilingualParityAndValidFormatSpecifiers() throws {
        let resourcesURL = repoRootURL.appendingPathComponent("Sources/BrisaApp/Resources")
        let requiredTables = [
            "Common",
            "MenuBar",
            "Overview",
            "Findings",
            "AppsAgents",
            "Activity",
            "Settings",
            "Tools",
            "Localizable"
        ]

        let issues = try StringsResourceValidator.validateDirectory(
            resourcesURL: resourcesURL,
            languages: ["es", "en"],
            requiredTables: requiredTables
        )
        XCTAssertTrue(issues.isEmpty, "Localization parity issues:\n" + issues.map(\.description).joined(separator: "\n"))
    }

    func testAllL10nCodeKeysExistInBothSpanishAndEnglishTables() throws {
        let localizationSwiftURL = repoRootURL.appendingPathComponent("Sources/BrisaApp/Localization.swift")
        let toolsLocalizationSwiftURL = repoRootURL.appendingPathComponent("Sources/BrisaApp/ToolsLocalization.swift")
        let source = try String(contentsOf: localizationSwiftURL, encoding: .utf8)
            + "\n"
            + (try String(contentsOf: toolsLocalizationSwiftURL, encoding: .utf8))

        let tableMap: [String: String] = [
            "common": "Common",
            "menuBar": "MenuBar",
            "overview": "Overview",
            "findings": "Findings",
            "appsAgents": "AppsAgents",
            "activity": "Activity",
            "settings": "Settings",
            "tools": "Tools"
        ]

        let pattern = #"L10n\.(?:tr|fmt)\(\.([a-zA-Z]+),\s*"([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        XCTAssertGreaterThan(matches.count, 100, "Expected modular L10n keys in Localization.swift")

        let resourcesURL = repoRootURL.appendingPathComponent("Sources/BrisaApp/Resources")
        var loadedTables: [String: [String: [String: String]]] = [:]
        for lang in ["es", "en"] {
            var langTables: [String: [String: String]] = [:]
            for tableName in Set(tableMap.values) {
                let tableURL = resourcesURL.appendingPathComponent("\(lang).lproj/\(tableName).strings")
                langTables[tableName] = try StringsResourceValidator.parseStringsFile(at: tableURL)
            }
            loadedTables[lang] = langTables
        }

        var missing: [String] = []
        for match in matches {
            let caseName = nsSource.substring(with: match.range(at: 1))
            let key = nsSource.substring(with: match.range(at: 2))
            guard let tableName = tableMap[caseName] else {
                missing.append("Unknown L10nTable .\(caseName) for key '\(key)'")
                continue
            }
            for lang in ["es", "en"] {
                if loadedTables[lang]?[tableName]?[key] == nil {
                    missing.append("\(lang).lproj/\(tableName).strings missing key '\(key)'")
                }
            }
        }

        XCTAssertTrue(missing.isEmpty, "Missing localization keys:\n" + missing.joined(separator: "\n"))
    }

    func testNoLegacyInlineBilingualLCallsRemainInBrisaApp() throws {
        let appDir = repoRootURL.appendingPathComponent("Sources/BrisaApp")
        let files = try FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])L\("#)

        var legacyHits: [String] = []
        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(location: 0, length: (content as NSString).length)
            if regex.firstMatch(in: content, range: range) != nil {
                legacyHits.append(file.lastPathComponent)
            }
        }
        XCTAssertTrue(legacyHits.isEmpty, "Legacy L(...) calls still present in: \(legacyHits.joined(separator: ", "))")
    }

    // MARK: - Live Hardware Telemetry & Breakdown Attribution

    func testParseProcessOutputPreservesPathsWithSpacesAndCommas() {
        let raw = """
          101     1   501  12,4  524288 /Applications/Visual Studio Code.app/Contents/MacOS/Electron
          202   101   501   3.6  131072 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
            1     0     0   0.5   65536 /sbin/launchd
        malformed line without numbers
        """
        let parsed = LiveHardwareBreakdownSampler.parseProcessOutput(raw)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].pid, 101)
        XCTAssertEqual(parsed[0].ppid, 1)
        XCTAssertEqual(parsed[0].uid, 501)
        XCTAssertEqual(parsed[0].rawCPUPercent, 12.4, accuracy: 0.001)
        XCTAssertEqual(parsed[0].rssBytes, 524_288 * 1024)
        XCTAssertEqual(parsed[0].commandPath, "/Applications/Visual Studio Code.app/Contents/MacOS/Electron")
        XCTAssertTrue(parsed[1].commandPath.hasSuffix("Google Chrome Helper (Renderer)"))
        XCTAssertEqual(parsed[2].uid, 0)
    }

    func testOuterBundleExtractionAndAncestryRollup() {
        let helperPath = "/Applications/Antigravity.app/Contents/Frameworks/Antigravity Helper (Renderer).app/Contents/MacOS/Antigravity Helper (Renderer)"
        XCTAssertEqual(
            LiveHardwareBreakdownSampler.extractOuterAppBundlePath(from: helperPath),
            "/Applications/Antigravity.app"
        )
        XCTAssertNil(LiveHardwareBreakdownSampler.extractOuterAppBundlePath(from: "/usr/libexec/logd"))

        let processes = [
            ParsedProcessSample(pid: 1, ppid: 0, uid: 0, rawCPUPercent: 1.0, rssBytes: 100 * 1_048_576, commandPath: "/sbin/launchd"),
            ParsedProcessSample(pid: 50, ppid: 1, uid: 501, rawCPUPercent: 20.0, rssBytes: 400 * 1_048_576, commandPath: "/Applications/Antigravity.app/Contents/MacOS/Antigravity"),
            ParsedProcessSample(pid: 51, ppid: 50, uid: 501, rawCPUPercent: 30.0, rssBytes: 600 * 1_048_576, commandPath: helperPath),
            ParsedProcessSample(pid: 52, ppid: 51, uid: 501, rawCPUPercent: 50.0, rssBytes: 200 * 1_048_576, commandPath: "/opt/homebrew/bin/node"),
            ParsedProcessSample(pid: 88, ppid: 1, uid: 88, rawCPUPercent: 10.0, rssBytes: 300 * 1_048_576, commandPath: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer")
        ]

        var metrics = MetricsSnapshot(memoryTotal: 16 * 1_073_741_824)
        metrics.memoryUsed = 2_600 * 1_048_576

        let snapshot = LiveHardwareBreakdownSampler.buildSnapshot(
            metrics: metrics,
            processes: processes,
            currentUID: 501,
            gpuTelemetry: nil,
            previousGPUTimes: nil,
            previousGPUSampleAt: nil,
            cpuCoreCount: 10,
            maxVisibleConsumers: 5,
            otherLabel: "Other",
            systemLabel: "macOS"
        )

        let antigravityMem = snapshot.memoryConsumers.first { $0.id == "app:/Applications/Antigravity.app" }
        XCTAssertEqual(antigravityMem?.displayName, "Antigravity")
        XCTAssertEqual(antigravityMem?.processCount, 3)
        XCTAssertEqual(antigravityMem?.primaryBytes, 1_200 * 1_048_576)

        // Reported per-process RSS for system daemons stays honest (launchd 100 MiB + WindowServer 300 MiB = 400 MiB),
        // without fabricating (memoryUsed - sum(RSS)) kernel overhead into macOS.
        let sysMem = snapshot.memoryConsumers.first { $0.kind == .system }
        XCTAssertEqual(sysMem?.displayName, "macOS")
        XCTAssertEqual(sysMem?.primaryBytes, 400 * 1_048_576)
        XCTAssertEqual(snapshot.totalObservedProcessRSSBytes, 1_600 * 1_048_576)

        let antigravityCPU = snapshot.cpuConsumers.first { $0.id == "app:/Applications/Antigravity.app" }
        XCTAssertEqual(antigravityCPU?.processCount, 3)
        // Raw 20 + 30 + 50 = 100% across 10 logical cores => 10% host CPU.
        XCTAssertEqual(antigravityCPU?.percent ?? -1, 10.0, accuracy: 0.001)
    }

    func testTopNConsolidatesTailIntoSingleOtherRow() {
        var processes: [ParsedProcessSample] = []
        for idx in 1...8 {
            processes.append(
                ParsedProcessSample(
                    pid: Int32(100 + idx),
                    ppid: 1,
                    uid: 501,
                    rawCPUPercent: Double((9 - idx) * 10),
                    rssBytes: UInt64((9 - idx) * 100 * 1_048_576),
                    commandPath: "/Applications/App\(idx).app/Contents/MacOS/App\(idx)"
                )
            )
        }

        var metrics = MetricsSnapshot(memoryTotal: 8 * 1_073_741_824)
        metrics.memoryUsed = processes.reduce(0) { $0 + $1.rssBytes }

        let snapshot = LiveHardwareBreakdownSampler.buildSnapshot(
            metrics: metrics,
            processes: processes,
            currentUID: 501,
            gpuTelemetry: nil,
            previousGPUTimes: nil,
            previousGPUSampleAt: nil,
            cpuCoreCount: 4,
            maxVisibleConsumers: 4,
            otherLabel: "Otros",
            systemLabel: "macOS"
        )

        XCTAssertEqual(snapshot.memoryConsumers.count, 5) // Top 4 + Otros
        let otherMem = snapshot.memoryConsumers.last
        XCTAssertEqual(otherMem?.id, "other:memory")
        XCTAssertEqual(otherMem?.kind, .other)
        XCTAssertEqual(otherMem?.displayName, "Otros")
        XCTAssertEqual(otherMem?.processCount, 4)
        XCTAssertEqual(otherMem?.primaryBytes, UInt64(400 + 300 + 200 + 100) * 1_048_576)

        XCTAssertEqual(snapshot.cpuConsumers.count, 5)
        XCTAssertEqual(snapshot.cpuConsumers.last?.id, "other:cpu")
    }

    func testGPUStatusUnavailableNeverFabricatesValuesAndComputesSafeDeltas() {
        let now = Date()
        let metrics = MetricsSnapshot(memoryTotal: 16 * 1_073_741_824)
        let processes = [
            ParsedProcessSample(pid: 10, ppid: 1, uid: 501, rawCPUPercent: 5, rssBytes: 100_000_000, commandPath: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"),
            ParsedProcessSample(pid: 20, ppid: 1, uid: 501, rawCPUPercent: 2, rssBytes: 100_000_000, commandPath: "/Applications/Claude.app/Contents/MacOS/Claude"),
            ParsedProcessSample(pid: 30, ppid: 1, uid: 88, rawCPUPercent: 1, rssBytes: 50_000_000, commandPath: "/System/Library/Frameworks/SkyLight.framework/WindowServer")
        ]

        // 1. Unavailable telemetry -> nil percentage, empty consumers, never fabricated.
        let unavailable = LiveHardwareBreakdownSampler.buildSnapshot(
            now: now,
            metrics: metrics,
            processes: processes,
            currentUID: 501,
            gpuTelemetry: nil,
            previousGPUTimes: nil,
            previousGPUSampleAt: nil
        )
        XCTAssertNil(unavailable.gpuUtilizationPercent)
        XCTAssertEqual(unavailable.gpuStatus, .unavailable)
        XCTAssertTrue(unavailable.gpuConsumers.isEmpty)

        // 2. First sample -> warming up while seeding baseline counters.
        let sample1 = IOAcceleratorTelemetry(
            deviceUtilizationPercent: 40,
            rendererUtilizationPercent: 38,
            tilerUtilizationPercent: 12,
            inUseSystemMemoryBytes: 512_000_000,
            clientAccumulatedGPUNanoseconds: [
                10: GPUClientUsageSample(pid: 10, creatorName: "pid 10, ChatGPT", accumulatedGPUNanoseconds: 1_000_000_000),
                20: GPUClientUsageSample(pid: 20, creatorName: "pid 20, Claude", accumulatedGPUNanoseconds: 5_000_000_000),
                30: GPUClientUsageSample(pid: 30, creatorName: "pid 30, WindowServer", accumulatedGPUNanoseconds: 3_000_000_000)
            ]
        )
        let warming = LiveHardwareBreakdownSampler.buildSnapshot(
            now: now,
            metrics: metrics,
            processes: processes,
            currentUID: 501,
            gpuTelemetry: sample1,
            previousGPUTimes: nil,
            previousGPUSampleAt: nil
        )
        XCTAssertEqual(warming.gpuUtilizationPercent, 40)
        XCTAssertEqual(warming.gpuStatus, .warmingUp)
        XCTAssertTrue(warming.gpuConsumers.isEmpty)

        // 3. Second sample -> computes delta shares, ignores counter resets cleanly (PID 20 reset < prev).
        let sample2 = IOAcceleratorTelemetry(
            deviceUtilizationPercent: 60,
            rendererUtilizationPercent: 58,
            tilerUtilizationPercent: 15,
            inUseSystemMemoryBytes: 600_000_000,
            clientAccumulatedGPUNanoseconds: [
                10: GPUClientUsageSample(pid: 10, creatorName: "pid 10, ChatGPT", accumulatedGPUNanoseconds: 1_300_000_000), // +300ms (75%)
                20: GPUClientUsageSample(pid: 20, creatorName: "pid 20, Claude", accumulatedGPUNanoseconds: 50_000_000),     // reset < prev -> ignored cleanly
                30: GPUClientUsageSample(pid: 30, creatorName: "pid 30, WindowServer", accumulatedGPUNanoseconds: 3_100_000_000) // +100ms (25%)
            ]
        )
        let active = LiveHardwareBreakdownSampler.buildSnapshot(
            now: now.addingTimeInterval(2),
            metrics: metrics,
            processes: processes,
            currentUID: 501,
            gpuTelemetry: sample2,
            previousGPUTimes: [10: 1_000_000_000, 20: 5_000_000_000, 30: 3_000_000_000],
            previousGPUSampleAt: now
        )
        XCTAssertEqual(active.gpuStatus, .available)
        XCTAssertEqual(active.gpuUtilizationPercent ?? -1, 60.0, accuracy: 0.001)
        XCTAssertEqual(active.gpuConsumers.count, 2)
        XCTAssertEqual(active.gpuConsumers[0].displayName, "ChatGPT")
        XCTAssertEqual(active.gpuConsumers[0].gpuDeltaNanoseconds, 300_000_000)
        XCTAssertEqual(active.gpuConsumers[0].percent ?? -1, 75.0, accuracy: 0.001) // 300ms / 400ms active Metal share
        XCTAssertEqual(active.gpuConsumers[1].kind, .system)
        XCTAssertEqual(active.gpuConsumers[1].gpuDeltaNanoseconds, 100_000_000)
        XCTAssertEqual(active.gpuConsumers[1].percent ?? -1, 25.0, accuracy: 0.001) // 100ms / 400ms active Metal share

        // 4. Unchanged counters -> idle state.
        let idle = LiveHardwareBreakdownSampler.buildSnapshot(
            now: now.addingTimeInterval(4),
            metrics: metrics,
            processes: processes,
            currentUID: 501,
            gpuTelemetry: sample2,
            previousGPUTimes: [10: 1_300_000_000, 20: 50_000_000, 30: 3_100_000_000],
            previousGPUSampleAt: now.addingTimeInterval(2)
        )
        XCTAssertEqual(idle.gpuStatus, .idle)
        XCTAssertTrue(idle.gpuConsumers.isEmpty)
    }

    func testParseIOUserClientCreator() {
        XCTAssertEqual(
            LiveHardwareBreakdownSampler.parseIOUserClientCreator("pid 482, WindowServer")?.pid,
            482
        )
        XCTAssertEqual(
            LiveHardwareBreakdownSampler.parseIOUserClientCreator("pid 482, WindowServer")?.name,
            "WindowServer"
        )
        XCTAssertEqual(
            LiveHardwareBreakdownSampler.parseIOUserClientCreator("pid 9123, Antigravity Helper (GPU), Extra")?.name,
            "Antigravity Helper (GPU), Extra"
        )
        XCTAssertNil(LiveHardwareBreakdownSampler.parseIOUserClientCreator("WindowServer"))
        XCTAssertNil(LiveHardwareBreakdownSampler.parseIOUserClientCreator("pid abc, WindowServer"))
    }

    func testHostTelemetryStaysRealAndMetricsSamplerGPUStaysNil() {
        let baseSampler = MetricsSampler()
        XCTAssertNil(baseSampler.sample().gpuPercent)

        let sampler = LiveHardwareBreakdownSampler()
        let first = sampler.sample()
        XCTAssertGreaterThan(first.metrics.memoryTotal, 0)
        XCTAssertFalse(first.memoryConsumers.isEmpty)
        if let gpu = first.gpuUtilizationPercent {
            XCTAssertTrue((0...100).contains(gpu))
        }
    }
}
