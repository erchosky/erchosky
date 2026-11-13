import Foundation
import Darwin

public enum ReadDecision: Equatable, Sendable {
    case allowed
    case deniedSensitive(String)
    case deniedUserProtected
    case deniedSymlink
    case deniedOutsideScope
}

public enum LocationAccessState: String, Codable, Equatable, Sendable {
    case explicitlyAuthorized = "explicitly_authorized"
    case accessible = "accessible"
    case deniedPermission = "denied_permission"
    case skippedInteractivePrompt = "skipped_interactive_prompt"
    case forbiddenSensitive = "forbidden_sensitive"
    case missing
    case unavailable
}

/// Governs read-only metadata discovery for the storage inventory.
/// Distinct from `SafetyPolicy`, which governs destructive cleanup operations.
/// Never reads file contents; permits metadata inspection of known developer, VM, package,
/// extension and session locations while strictly excluding credentials, keychains and personal stores.
public struct ReadAuthorizationPolicy: Sendable {
    public let home: String
    public let projectRoots: [String]
    public let protectedPaths: [String]
    public let allowSystemLocations: Bool
    public let systemRootPrefix: String?
    public let avoidInteractiveTCCPrompts: Bool
    /// Roots selected in a current native authorization flow, never inferred from stored paths.
    public let authorizedPromptRoots: [String]

    private let homeLower: String
    private let defaultCachesLower: String
    private let defaultLogsLower: String
    private let protectedPathsLower: [String]
    private let explicitProjectRootsLower: [String]
    private let explicitAuthorizedPromptRootsLower: [String]
    private let tccPromptRootsLower: [String]
    private let containersRootLower: String
    private let groupContainersRootLower: String
    private let savedAppStateLower: String
    private let documentsPrefixLower: String
    private let vmDocumentsPrefixLower: String
    private let picturesPrefixLower: String
    private let forbiddenFullPrefixesLower: [(prefix: String, reason: String)]
    private let resolvedAllowedSystemPrefixes: [String]

    public static let realUserHome: String = Paths.normalized(NSHomeDirectory())

    public init(
        home: String = NSHomeDirectory(),
        projectRoots: [String] = [],
        protectedPaths: [String] = [],
        allowSystemLocations: Bool = true,
        systemRootPrefix: String? = nil,
        avoidInteractiveTCCPrompts: Bool? = nil,
        authorizedPromptRoots: [String] = []
    ) {
        let normalizedHome = Paths.normalized(home)
        let normalizedProjectRoots = projectRoots.map(Paths.normalized)
        let normalizedProtectedPaths = protectedPaths.map(Paths.normalized)
        let normalizedSystemRootPrefix = systemRootPrefix.map(Paths.normalized)
        let normalizedAuthorizedPromptRoots = authorizedPromptRoots.map(Paths.normalized)

        self.home = normalizedHome
        self.projectRoots = normalizedProjectRoots
        self.protectedPaths = normalizedProtectedPaths
        self.allowSystemLocations = allowSystemLocations
        self.systemRootPrefix = normalizedSystemRootPrefix
        self.avoidInteractiveTCCPrompts = avoidInteractiveTCCPrompts ?? (normalizedHome == Self.realUserHome)
        self.authorizedPromptRoots = normalizedAuthorizedPromptRoots

        let hLower = normalizedHome.lowercased()
        let cachesLower = hLower + "/library/caches"
        let logsLower = hLower + "/library/logs"
        self.homeLower = hLower
        self.defaultCachesLower = cachesLower
        self.defaultLogsLower = logsLower
        self.protectedPathsLower = normalizedProtectedPaths.map { $0.lowercased() }
        self.explicitProjectRootsLower = normalizedProjectRoots
            .map { $0.lowercased() }
            .filter { !SafetyPolicy.within($0, cachesLower) && !SafetyPolicy.within($0, logsLower) }
        self.explicitAuthorizedPromptRootsLower = normalizedAuthorizedPromptRoots
            .map { $0.lowercased() }
            .filter { !SafetyPolicy.within($0, cachesLower) && !SafetyPolicy.within($0, logsLower) }
        self.tccPromptRootsLower = [
            hLower + "/downloads",
            hLower + "/desktop",
            hLower + "/documents",
            hLower + "/movies",
            hLower + "/music",
            hLower + "/pictures"
        ]
        self.containersRootLower = hLower + "/library/containers/"
        self.groupContainersRootLower = hLower + "/library/group containers/"
        self.savedAppStateLower = hLower + "/library/saved application state"
        self.documentsPrefixLower = hLower + "/documents"
        self.vmDocumentsPrefixLower = hLower + "/documents/virtual machines.localized"
        self.picturesPrefixLower = hLower + "/pictures"
        self.forbiddenFullPrefixesLower = Self.forbiddenHomeRelativePrefixes.map {
            (prefix: (normalizedHome + "/" + $0).lowercased(), reason: "forbidden_store:\($0)")
        }
        if let sysPrefix = normalizedSystemRootPrefix {
            self.resolvedAllowedSystemPrefixes = Self.allowedSystemPrefixes.map { sysPrefix + $0 }
        } else if allowSystemLocations {
            self.resolvedAllowedSystemPrefixes = Self.allowedSystemPrefixes
        } else {
            self.resolvedAllowedSystemPrefixes = []
        }
    }

    /// Validates a folder for read-only inventory authorization (e.g. `~/Downloads` or a project folder).
    /// Unlike `SafetyPolicy`, this permits authorizing `~/Downloads` or project folders for inventory
    /// without granting destructive cleanup rights over personal documents.
    public static func validateInventoryRoot(
        _ rawPath: String,
        home: String = NSHomeDirectory(),
        protectedPaths: [String] = []
    ) throws -> String {
        let canonicalHome = Paths.normalized(home)
        guard rawPath.hasPrefix("/"), !rawPath.contains("\0"), rawPath.utf8.count < 4096 else {
            throw BrisaError.invalid("Absolute root required")
        }
        let normalized = Paths.normalized(rawPath)
        guard normalized != "/", normalized != canonicalHome, SafetyPolicy.within(normalized, canonicalHome) else {
            throw BrisaError.rejected("Choose a directory inside your home, not the home directory itself")
        }
        try SafetyPolicy.rejectSymlinks(normalized)
        var st = stat()
        guard lstat(normalized, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else {
            throw BrisaError.rejected("Root is not an owned directory")
        }
        let policy = ReadAuthorizationPolicy(
            home: canonicalHome,
            projectRoots: [normalized],
            protectedPaths: protectedPaths,
            allowSystemLocations: false,
            avoidInteractiveTCCPrompts: false
        )
        switch policy.evaluate(normalized, checkSymlinks: true) {
        case .allowed:
            return normalized
        case .deniedSensitive(let why):
            throw BrisaError.rejected("Sensitive location cannot be added to inventory (\(why))")
        case .deniedUserProtected:
            throw BrisaError.rejected("Protected by user settings")
        case .deniedSymlink:
            throw BrisaError.rejected("Symbolic link in path")
        case .deniedOutsideScope:
            throw BrisaError.rejected("Outside authorized inventory scope")
        }
    }

    public func locationAccessState(_ rawPath: String) -> LocationAccessState {
        let path = Paths.normalized(rawPath)
        let eval = evaluate(path, checkSymlinks: false)
        if eval != .allowed {
            return .forbiddenSensitive
        }
        let lower = path.lowercased()
        if requiresUnauthedTCCPrompt(normalizedLower: lower) {
            return .skippedInteractivePrompt
        }
        var st = stat()
        if lstat(path, &st) != 0 {
            if errno == EACCES || errno == EPERM { return .deniedPermission }
            return errno == ENOENT ? .missing : .unavailable
        }
        guard st.st_mode & S_IFMT == S_IFDIR, !Self.hasSymlinkComponent(path) else { return .unavailable }
        if explicitProjectRootsLower.contains(where: { SafetyPolicy.within(lower, $0) }) {
            return .explicitlyAuthorized
        }
        return .accessible
    }

    private static let tccAppleCaches: [String] = [
        "/com.apple.music",
        "/com.apple.amp",
        "/com.apple.itunes",
        "/com.apple.tv",
        "/com.apple.podcasts",
        "/com.apple.applemediaservices",
        "/com.apple.homekit",
        "/com.apple.safari",
        "/com.apple.icloud",
        "/com.apple.bird",
        "/com.apple.ap.adprivacyd",
        "/cloudkit",
        "/familycircle",
        "/passkit"
    ]

    /// Returns true when probing `rawPath` on the live user home without explicit user folder authorization
    /// could trigger a blocking macOS modal prompt (`tccd` `preflight=no`) or protected container dialog.
    /// Does not claim to detect Full Disk Access globally.
    public func requiresUnauthedTCCPrompt(_ rawPath: String) -> Bool {
        guard avoidInteractiveTCCPrompts else { return false }
        let path = Paths.normalized(rawPath)
        return requiresUnauthedTCCPrompt(normalizedLower: path.lowercased())
    }

    private func requiresUnauthedTCCPrompt(normalizedLower lower: String) -> Bool {
        guard avoidInteractiveTCCPrompts else { return false }
        if explicitAuthorizedPromptRootsLower.contains(where: { SafetyPolicy.within(lower, $0) }) {
            return false
        }

        // 1. User folders gated by interactive TCC prompts (Downloads, Desktop, Documents, Movies, Music, Pictures)
        if tccPromptRootsLower.contains(where: { SafetyPolicy.within(lower, $0) }) {
            return true
        }

        // 2. Apple MediaLibrary / HomeKit / Safari / CloudKit system caches inside ~/Library/Caches that trigger TCC prompts without FDA
        if SafetyPolicy.within(lower, defaultCachesLower) {
            let rel = lower.dropFirst(defaultCachesLower.count)
            if Self.tccAppleCaches.contains(where: { rel.hasPrefix($0) }) {
                return true
            }
        }

        // 3. App Sandbox Containers and Group Containers gated by kTCCServiceSystemPolicyAppData / kTCCServiceMediaLibrary without FDA
        if lower.hasPrefix(containersRootLower) {
            let rest = lower.dropFirst(containersRootLower.count)
            let firstSegment = rest[..<(rest.firstIndex(of: "/") ?? rest.endIndex)]
            if firstSegment != "com.docker.docker" {
                return true
            }
        }
        if lower.hasPrefix(groupContainersRootLower) {
            let rest = lower.dropFirst(groupContainersRootLower.count)
            let container = rest[..<(rest.firstIndex(of: "/") ?? rest.endIndex)]
            let suffix = ".dev.orbstack"
            let team = container.hasSuffix(suffix) ? container.dropLast(suffix.count) : Substring("")
            if team.count != 10 || !team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                return true
            }
        }

        // 4. Saved Application State (macOS protects other apps' saved state under App Data TCC without FDA)
        if SafetyPolicy.within(lower, savedAppStateLower) {
            return true
        }

        return false
    }

    static let forbiddenHomeRelativePrefixes: [String] = [
        ".ssh",
        ".gnupg",
        ".aws",
        ".azure",
        ".Trash",
        ".colima/_lima/_config",
        ".colima/_lima/_networks",
        ".lima/_config",
        ".lima/_networks",
        ".orbstack/config",
        ".docker/certs.d",
        "Library/Keychains",
        "Library/Accounts",
        "Library/IdentityServices",
        "Library/Mail",
        "Library/Messages",
        "Library/Mobile Documents",
        "Library/CloudStorage",
        "Library/Calendars",
        "Library/Reminders",
        "Library/PersonalizationPortrait",
        "Library/Suggestions",
        "Library/HomeKit",
        "Library/Sharing",
        "Library/Biome",
        "Library/DoNotDisturb",
        "Library/StatusKit",
        "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB",
        "Library/Application Support/CallHistoryTransactions",
        "Library/Application Support/com.apple.TCC",
        "Library/Application Support/Knowledge",
        "Library/Application Support/CloudDocs",
        "Library/Application Support/FileProvider",
        "Library/Application Support/MobileSync/Backup",
        "Library/Application Support/Signal/attachments.noindex",
        "Library/Application Support/minecraft/saves",
        "Library/Application Support/Blackmagic Design/DaVinci Resolve/Resolve Disk Database",
        "Library/Group Containers/UBF8T346G9.Office/Outlook",
        "Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message",
        "Library/Group Containers/group.net.whatsapp.WhatsAppSMB.shared/Message",
        "Movies/TV/Media",
        "Movies/TV/Media.localized",
        "Music/Music/Media.localized",
        "Music/iTunes/iTunes Media"
    ]

    private static let allowedSystemPrefixes: [String] = [
        "/Applications",
        "/Library/Developer",
        "/Library/Logs/DiagnosticReports",
        "/private/tmp",
        "/private/var/folders",
        "/private/var/tmp",
        "/opt/local/var/macports",
        "/Users/Shared/Epic Games"
    ]

    public func isMetadataAllowed(_ rawPath: String, checkSymlinks: Bool = true) -> Bool {
        evaluate(rawPath, checkSymlinks: checkSymlinks) == .allowed
    }

    enum ChildAccessOutcome {
        case allowed
        case tccPromptRequired
        case denied
    }

    /// Evaluates both interactive-TCC preflight and read authorization in a single normalized lowercase pass.
    func evaluateChildForMeasurement(_ rawPath: String) -> ChildAccessOutcome {
        guard let lower = validatedNormalizedLower(rawPath) else { return .denied }
        if requiresUnauthedTCCPrompt(normalizedLower: lower) {
            return .tccPromptRequired
        }
        return evaluateNormalized(path: rawPath, lower: lower, checkSymlinks: false) == .allowed ? .allowed : .denied
    }

    public func evaluate(_ rawPath: String, checkSymlinks: Bool = true) -> ReadDecision {
        guard let lower = validatedNormalizedLower(rawPath) else {
            return .deniedOutsideScope
        }
        return evaluateNormalized(path: rawPath, lower: lower, checkSymlinks: checkSymlinks)
    }

    private func validatedNormalizedLower(_ rawPath: String) -> String? {
        guard rawPath.hasPrefix("/") else { return nil }
        var isPureASCII = true
        for byte in rawPath.utf8 {
            if byte == 0 || byte < 32 || byte == 127 { return nil }
            if byte >= 128 { isPureASCII = false }
        }
        if !isPureASCII {
            if rawPath.unicodeScalars.contains(where: { $0.properties.generalCategory == .format }) {
                return nil
            }
        }
        guard Paths.isAlreadyNormalized(rawPath) else { return nil }
        return rawPath.lowercased()
    }

    private func evaluateNormalized(path: String, lower: String, checkSymlinks: Bool) -> ReadDecision {
        if protectedPathsLower.contains(where: { SafetyPolicy.within(lower, $0) }) {
            return .deniedUserProtected
        }

        // Check forbidden home-relative stores
        for entry in forbiddenFullPrefixesLower {
            if SafetyPolicy.within(lower, entry.prefix) {
                return .deniedSensitive(entry.reason)
            }
        }

        // Check path components for sensitive names, credentials, keys, memory stores, or photos libraries
        var prev1: Substring = ""
        var prev2: Substring = ""
        var prev3: Substring = ""
        var sawBrisaInternal = false
        var segmentStart = lower.index(after: lower.startIndex)
        while segmentStart <= lower.endIndex {
            let slash = lower[segmentStart...].firstIndex(of: "/") ?? lower.endIndex
            let part = lower[segmentStart..<slash]
            if !part.isEmpty {
                if part == ".ssh" || part == ".gnupg" || part == "keychains" || part == ".trash" {
                    return .deniedSensitive("sensitive_component:\(part)")
                }
                if part.hasPrefix(".env") || part.hasSuffix(".photoslibrary") || part.hasSuffix(".pem") || part.hasSuffix(".key") {
                    return .deniedSensitive("sensitive_file:\(part)")
                }
                if part == "id_rsa" || part == "id_rsa.pub" || part == "id_ed25519" || part == "id_ed25519.pub" ||
                   part == ".npmrc" || part == ".pypirc" || part == ".netrc" || part == "auth.json" {
                    return .deniedSensitive("credential_file:\(part)")
                }
                if part.contains("credential") || part.contains("secret") || part == "cookies" || part == "cookies-journal" {
                    return .deniedSensitive("secret_name:\(part)")
                }
                // Never touch Claude Code memory directories (**/.claude*/projects/*/memory)
                if part == "memory", prev2 == "projects", prev3.hasPrefix(".claude") {
                    return .deniedSensitive("claude_memory")
                }
                if !sawBrisaInternal && (part == "dev.brisa.ipc" || part == "dev.brisa.build" ||
                   part.hasPrefix("brisabuild.") || part.hasPrefix("brisasnapshot.") || part.hasPrefix("brisamcp.")) {
                    sawBrisaInternal = true
                }
                prev3 = prev2
                prev2 = prev1
                prev1 = part
            }
            if slash == lower.endIndex { break }
            segmentStart = lower.index(after: slash)
        }

        // Avoid Brisa's own active IPC socket directory or disposable build/test snapshots in /private/tmp
        if sawBrisaInternal {
            return .deniedSensitive("brisa_internal")
        }

        // Scope check: must be inside `home`, an authorized `projectRoot`, or an allowed system prefix
        let inHome = path != home && SafetyPolicy.within(path, home)
        let inProjectRoot = projectRoots.contains { SafetyPolicy.within(path, $0) }
        let inSystem = !resolvedAllowedSystemPrefixes.isEmpty && resolvedAllowedSystemPrefixes.contains { SafetyPolicy.within(path, $0) }

        guard inHome || inProjectRoot || inSystem else {
            return .deniedOutsideScope
        }

        // If inside ~/Documents, ~/Desktop, or ~/Pictures, only allow specific catalog patterns (like Virtual Machines or installer files)
        if SafetyPolicy.within(lower, documentsPrefixLower),
           !inProjectRoot,
           !SafetyPolicy.within(lower, vmDocumentsPrefixLower) {
            return .deniedSensitive("personal_documents")
        }
        if SafetyPolicy.within(lower, picturesPrefixLower),
           !lower.contains("lightroom library.lrlibrary") {
            return .deniedSensitive("personal_pictures")
        }

        if checkSymlinks {
            if Self.hasSymlinkComponent(path, stopAt: inHome ? home : (systemRootPrefix ?? "/")) {
                return .deniedSymlink
            }
        }

        return .allowed
    }

    public static func hasSymlinkComponent(_ path: String, stopAt: String = "/") -> Bool {
        var current = ""
        let normalizedStop = Paths.normalized(stopAt)
        for component in path.split(separator: "/") {
            current += "/" + component
            if current.count <= normalizedStop.count && SafetyPolicy.within(normalizedStop, current) && current != path {
                continue
            }
            var st = stat()
            if lstat(current, &st) != 0 {
                return true
            }
            if (st.st_mode & S_IFMT) == S_IFLNK {
                return true
            }
        }
        return false
    }
}
