import Foundation

public struct SystemEnvironmentSnapshot: Sendable {
    public let runningProcessNames: Set<String>
    public let hasActiveAgent: Bool
    public let installedBundleIDs: Set<String>
    public let installedAppNames: Set<String>
    public let processInspectionAvailable: Bool
    public let applicationInspectionComplete: Bool

    public init(
        runningProcessNames: Set<String> = [],
        hasActiveAgent: Bool = false,
        installedBundleIDs: Set<String> = [],
        installedAppNames: Set<String> = [],
        processInspectionAvailable: Bool = true,
        applicationInspectionComplete: Bool = true
    ) {
        self.runningProcessNames = runningProcessNames
        self.hasActiveAgent = hasActiveAgent
        self.installedBundleIDs = installedBundleIDs
        self.installedAppNames = installedAppNames
        self.processInspectionAvailable = processInspectionAvailable
        self.applicationInspectionComplete = applicationInspectionComplete
    }

    public static func capture(home: String = NSHomeDirectory(), includeSystemApps: Bool = true,
                               control: ScanControl = ScanControl()) -> SystemEnvironmentSnapshot {
        var procNames = Set<String>()
        var activeAgent = false
        var processInspectionAvailable = false
        if let list = try? ProcessInspector.list(control: control) {
            processInspectionAvailable = true
            for entry in list {
                let baseLower = URL(fileURLWithPath: entry.executable).lastPathComponent.lowercased()
                procNames.insert(baseLower)
                for part in entry.executable.split(separator: "/") where part.lowercased().hasSuffix(".app") {
                    procNames.insert(String(part.dropLast(4)).lowercased())
                }
                if entry.isAgent {
                    activeAgent = true
                }
            }
        }

        var bundleIDs = Set<String>()
        var appNames = Set<String>()
        var appDirs = [home + "/Applications"]
        if includeSystemApps {
            appDirs.append("/Applications")
            appDirs.append("/System/Applications")
        }

        let applications = ApplicationDiscovery.discover(in: appDirs, control: control)
        for url in applications.urls {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            appNames.insert(name)
            if let bid = Bundle(url: url)?.bundleIdentifier?.lowercased() {
                bundleIDs.insert(bid)
            }
        }

        return SystemEnvironmentSnapshot(
            runningProcessNames: procNames,
            hasActiveAgent: activeAgent,
            installedBundleIDs: bundleIDs,
            installedAppNames: appNames,
            processInspectionAvailable: processInspectionAvailable,
            applicationInspectionComplete: applications.complete
        )
    }
}

public struct PolicyEvaluation: Equatable, Sendable {
    public let eligible: Bool
    public let inventoryOnly: Bool
    public let selectionAllowed: Bool
    public let cleanupEligibility: CleanupEligibility
    public let usageState: UsageState
    public let reason: String
    public let confidence: String
    public let reclaimableBytes: Int64
    public let conditionsSummary: [String]
}

public enum SelectionPolicy {
    public static func hasIdleParents(path: String, root: String, now: Date = Date()) -> Bool {
        var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        while SafetyPolicy.within(parent.path, root) {
            guard let values = try? parent.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) >= 86400 else {
                return false
            }
            if parent.path == root { break }
            parent.deleteLastPathComponent()
        }
        return true
    }

    public static func isPlausibleUninstalledLeftover(
        path: String,
        ruleID: String,
        snapshot: SystemEnvironmentSnapshot
    ) -> Bool {
        guard snapshot.applicationInspectionComplete else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        let lower = name.lowercased()

        // Exclude Apple/macOS system containers, preferences, and frameworks
        let applePrefixes = [
            "com.apple.", "group.com.apple.", "systemgroup.com.apple.", "apple",
            "mobilemeaccounts", "contextstoreagent", "clouddocs", "familycircle",
            "byhost", ".globalpreferences", "loginwindow", "pbs", "sharedfilelistd"
        ]
        if applePrefixes.contains(where: { lower.hasPrefix($0) }) || lower.contains(".com.apple.") {
            return false
        }
        // Exclude Brisa's own state directory and generic system folder names
        if lower == "brisa" || lower.hasPrefix("dev.brisa") || lower == "caches" || lower == "crashreporter" || lower == "logs" {
            return false
        }

        let baseIdentifier: String = {
            if lower.hasSuffix(".plist") {
                return String(lower.dropLast(6))
            }
            return lower
        }()

        // If bundle ID matches an installed app directly or as a prefix/group container
        if snapshot.installedBundleIDs.contains(baseIdentifier) {
            return false
        }
        if snapshot.installedBundleIDs.contains(where: {
            baseIdentifier.hasPrefix($0 + ".") || baseIdentifier.hasSuffix("." + $0)
        }) {
            return false
        }

        // If folder name matches an installed app name
        if snapshot.installedAppNames.contains(baseIdentifier) {
            return false
        }
        let normalizedTokens = baseIdentifier.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        if snapshot.installedAppNames.contains(normalizedTokens) {
            return false
        }

        return true
    }

    public static func evaluate(
        rule: CatalogRule,
        measurement: MeasurementResult,
        safetyPolicy: SafetyPolicy?,
        snapshot: SystemEnvironmentSnapshot,
        now: Date = Date(),
        openFileCheck: ((String) throws -> [Int32])? = nil,
        forceInventoryOnly: Bool = false
    ) -> PolicyEvaluation {
        var conditions: [String] = []
        if rule.listOnly || forceInventoryOnly || !snapshot.processInspectionAvailable {
            conditions.append("listOnly=true")
        }
        if rule.neverTicked || rule.tier == .never {
            conditions.append("neverSelect=true")
        }
        if rule.requiresTypedAdapter, let tool = rule.adapterTool {
            conditions.append("adapter:\(tool)(unimplemented)")
        }
        if !rule.near.isEmpty {
            conditions.append("near:\(rule.near.joined(separator: ","))")
        }
        if !rule.inside.isEmpty {
            conditions.append("inside:\(rule.inside.joined(separator: ","))")
        }
        if !rule.notInside.isEmpty {
            conditions.append("notInside:\(rule.notInside.joined(separator: ","))")
        }
        if let days = rule.rule.untouchedDays ?? rule.rule.projectUntouchedDays {
            conditions.append("untouchedDays>=\(days)")
        }
        if rule.hasUnverifiedCondition {
            conditions.append("smartRule:unverified_locked")
        }

        // 1. Check active processes from snapshot
        var matchedRunningProcess: String? = nil
        if let procs = rule.rule.processes {
            for proc in procs {
                let pLower = proc.lowercased()
                if snapshot.runningProcessNames.contains(pLower) {
                    matchedRunningProcess = proc
                    break
                }
            }
        }

        let requiredDays = max(rule.rule.untouchedDays ?? rule.rule.projectUntouchedDays ?? 7, 7)
        let ageSeconds = now.timeIntervalSince(measurement.modifiedAt)
        let isRecent = ageSeconds < Double(requiredDays) * 86400

        var usageState = UsageState(status: "unknown", detail: "not_checked")
        if let proc = matchedRunningProcess {
            usageState = UsageState(status: "active_process", detail: proc)
            conditions.append("processActive:\(proc)")
        } else if isRecent {
            usageState = UsageState(status: "recently_modified", detail: "< \(requiredDays)d")
        }

        // 2. Enforce strict separation of inventory vs selection vs cleanup
        if rule.neverTicked || rule.tier == .never {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .lockedNeverSelect,
                usageState: usageState,
                reason: "never_select",
                confidence: "inventory",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        if rule.listOnly || forceInventoryOnly || !snapshot.processInspectionAvailable {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .inventoryOnly,
                usageState: usageState,
                reason: "inventory_only",
                confidence: "inventory",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        if rule.requiresTypedAdapter {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .lockedRequiresTypedAdapter,
                usageState: usageState,
                reason: "requires_typed_adapter",
                confidence: "inventory",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        if rule.hasUnverifiedCondition {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .lockedUnverifiedCondition,
                usageState: usageState,
                reason: "unverified_condition",
                confidence: "inventory",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        if matchedRunningProcess != nil {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .lockedActiveProcess,
                usageState: usageState,
                reason: "active_process",
                confidence: "none",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        if measurement.isDirectory {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .lockedDirectoryBundle,
                usageState: usageState,
                reason: "directory_bundle_protected",
                confidence: "inventory",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        // 3. Regular file: must also satisfy SafetyPolicy, idle parent checks, and open-descriptor (lsof) verification
        if let safetyPolicy, let inspected = try? safetyPolicy.inspect(measurement.path, now: now) {
            if inspected.eligible && !isRecent {
                if snapshot.hasActiveAgent {
                    return PolicyEvaluation(
                        eligible: false,
                        inventoryOnly: true,
                        selectionAllowed: false,
                        cleanupEligibility: .lockedActiveAgent,
                        usageState: UsageState(status: "active_process", detail: "coding_agent"),
                        reason: "open_or_uncertain",
                        confidence: "none",
                        reclaimableBytes: 0,
                        conditionsSummary: conditions
                    )
                }
                if Self.hasIdleParents(path: inspected.path, root: inspected.root, now: now) {
                    do {
                        let openPIDs = try openFileCheck?(measurement.path) ?? ProcessInspector.openPIDs(measurement.path)
                        if !openPIDs.isEmpty {
                            let pidList = openPIDs.prefix(4).map(String.init).joined(separator: ",")
                            conditions.append("openDescriptor:pid=\(pidList)")
                            return PolicyEvaluation(
                                eligible: false,
                                inventoryOnly: true,
                                selectionAllowed: false,
                                cleanupEligibility: .lockedOpenFile,
                                usageState: UsageState(status: "open_file", detail: "PID \(pidList)"),
                                reason: "open_or_uncertain",
                                confidence: "none",
                                reclaimableBytes: 0,
                                conditionsSummary: conditions
                            )
                        }
                        conditions.append("openDescriptor:none_verified")
                        return PolicyEvaluation(
                            eligible: true,
                            inventoryOnly: false,
                            selectionAllowed: true,
                            cleanupEligibility: .eligible,
                            usageState: .idle,
                            reason: inspected.reason,
                            confidence: "medium",
                            reclaimableBytes: measurement.allocatedBytes,
                            conditionsSummary: conditions
                        )
                    } catch {
                        conditions.append("openDescriptor:check_failed")
                        return PolicyEvaluation(
                            eligible: false,
                            inventoryOnly: true,
                            selectionAllowed: false,
                            cleanupEligibility: .lockedOpenFile,
                            usageState: UsageState(status: "unknown", detail: "lsof_unavailable"),
                            reason: "open_or_uncertain",
                            confidence: "none",
                            reclaimableBytes: 0,
                            conditionsSummary: conditions
                        )
                    }
                } else {
                    return PolicyEvaluation(
                        eligible: false,
                        inventoryOnly: true,
                        selectionAllowed: false,
                        cleanupEligibility: .lockedRecent,
                        usageState: UsageState(status: "recently_modified", detail: "parent < 24h"),
                        reason: "open_or_uncertain",
                        confidence: "none",
                        reclaimableBytes: 0,
                        conditionsSummary: conditions
                    )
                }
            } else if isRecent || inspected.reason == "recent_file" {
                return PolicyEvaluation(
                    eligible: false,
                    inventoryOnly: true,
                    selectionAllowed: false,
                    cleanupEligibility: .lockedRecent,
                    usageState: UsageState(status: "recently_modified", detail: "< \(requiredDays)d"),
                    reason: "recent_file",
                    confidence: "none",
                    reclaimableBytes: 0,
                    conditionsSummary: conditions
                )
            }
        }

        if isRecent {
            return PolicyEvaluation(
                eligible: false,
                inventoryOnly: true,
                selectionAllowed: false,
                cleanupEligibility: .lockedRecent,
                usageState: usageState,
                reason: "recent_file",
                confidence: "none",
                reclaimableBytes: 0,
                conditionsSummary: conditions
            )
        }

        return PolicyEvaluation(
            eligible: false,
            inventoryOnly: true,
            selectionAllowed: false,
            cleanupEligibility: .lockedProtectedScope,
            usageState: usageState,
            reason: "inventory_only",
            confidence: "inventory",
            reclaimableBytes: 0,
            conditionsSummary: conditions
        )
    }
}
