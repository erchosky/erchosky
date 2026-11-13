import Foundation

/// Supported UI languages with clean extensibility for future localizations.
/// Adding a new language requires adding a case here (and to `concreteCases`) plus
/// matching `<code>.lproj/*.strings` resource tables.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case es
    case en

    public var id: String { rawValue }

    /// Concrete bundled languages backed by `<rawValue>.lproj` resource folders.
    public static let concreteLanguages: [AppLanguage] = [.es, .en]

    /// Default fallback concrete language when neither user preference nor system
    /// locale matches a bundled language.
    public static let fallbackLanguage: AppLanguage = .en

    /// Resolves any stored preference string (including `"system"` or regional tags)
    /// into a validated stored preference value (`"system"`, `"es"`, or `"en"`).
    public static func sanitizedPreference(_ rawValue: String?) -> String {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let match = Self(rawValue: normalized) else {
            return AppLanguage.system.rawValue
        }
        return match.rawValue
    }

    /// Resolves a preference into a concrete bundled language (`.es` or `.en`),
    /// honoring system preferred languages when set to `.system`.
    public static func resolve(
        preference: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        let sanitized = sanitizedPreference(preference)
        if let explicit = Self(rawValue: sanitized), explicit != .system {
            return explicit
        }
        for tag in preferredLanguages {
            let prefix = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map(String.init)
            if let prefix, let matched = concreteLanguages.first(where: { $0.rawValue == prefix }) {
                return matched
            }
        }
        return fallbackLanguage
    }

    /// Two-letter concrete language code (`"es"` or `"en"`). Never `"system"`.
    public func concreteCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if self == .system {
            return Self.resolve(preference: rawValue, preferredLanguages: preferredLanguages).rawValue
        }
        return rawValue
    }

    /// Native display name shown so users can always recognize their language even
    /// when another language is active.
    public var nativeName: String {
        switch self {
        case .system: return "System"
        case .es: return "Español"
        case .en: return "English"
        }
    }

    public var locale: Locale {
        switch self {
        case .system: return .current
        case .es: return Locale(identifier: "es")
        case .en: return Locale(identifier: "en")
        }
    }
}

/// Safely locates resource bundles both when executed via SwiftPM (`swift run` / `swift test`)
/// and when packaged inside `Brisa.app/Contents/Resources/<bundleName>.bundle`.
public enum ResourceBundleLocator {
    public static func locate(named bundleName: String, moduleBundle: () -> Bundle?) -> Bundle? {
        let bundleFolder = bundleName.hasSuffix(".bundle") ? bundleName : "\(bundleName).bundle"

        if let mainResource = Bundle.main.resourceURL {
            let nested = mainResource.appendingPathComponent(bundleFolder)
            if let loaded = Bundle(url: nested) {
                return loaded
            }
        }

        if let direct = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
           let loaded = Bundle(url: direct) {
            return loaded
        }

        if let arg0 = CommandLine.arguments.first {
            let execDir = URL(fileURLWithPath: arg0).standardizedFileURL.deletingLastPathComponent()
            let candidates = [
                execDir.appendingPathComponent(bundleFolder),
                execDir.appendingPathComponent("../Resources/\(bundleFolder)").standardizedFileURL,
                execDir.appendingPathComponent("Brisa.app/Contents/Resources/\(bundleFolder)")
            ]
            for candidate in candidates {
                if let loaded = Bundle(url: candidate) {
                    return loaded
                }
            }
        }

        // Only evaluate SwiftPM's moduleBundle when not running inside a packaged .app bundle
        // where missing top-level bundle files could otherwise trap inside SPM's accessor.
        let isPackagedApp = Bundle.main.bundleURL.pathExtension == "app"
        let hasTopLevelModuleBundle = FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL.appendingPathComponent(bundleFolder).path
        )
        if !isPackagedApp || hasTopLevelModuleBundle {
            return moduleBundle()
        }

        return Bundle.main
    }
}

/// Parses `.strings` files and verifies multi-language parity and format specifiers.
public enum StringsResourceValidator {
    public struct TableParityIssue: Equatable, CustomStringConvertible {
        public let table: String
        public let detail: String

        public var description: String { "\(table): \(detail)" }
    }

    public static func parseStringsFile(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: String] else {
            throw BrisaError.invalid("Invalid .strings dictionary format at \(url.path)")
        }
        return dict
    }

    /// Extracts ordered printf-style placeholders (`%@`, `%lld`, `%d`, `%.1f`, `%1$@`, etc.).
    public static func formatSpecifiers(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h|z)?[@dDuUxXoOfeEgGcCsSp%]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches
            .map { nsText.substring(with: $0.range) }
            .filter { $0 != "%%" }
    }

    /// Checks a directory containing `<lang>.lproj/*.strings` for symmetric tables,
    /// identical key sets, non-empty translations, and matching format specifiers.
    public static func validateDirectory(
        resourcesURL: URL,
        languages: [String] = AppLanguage.concreteLanguages.map(\.rawValue),
        requiredTables: [String] = []
    ) throws -> [TableParityIssue] {
        guard !languages.isEmpty else { return [] }
        let fm = FileManager.default
        var issues: [TableParityIssue] = []

        var tablesByLang: [String: [String: [String: String]]] = [:]
        var allTables = Set(requiredTables)

        for lang in languages {
            let lprojURL = resourcesURL.appendingPathComponent("\(lang).lproj")
            guard fm.fileExists(atPath: lprojURL.path) else {
                issues.append(TableParityIssue(table: "*", detail: "Missing \(lang).lproj directory"))
                continue
            }
            let items = try fm.contentsOfDirectory(at: lprojURL, includingPropertiesForKeys: nil)
            var tables: [String: [String: String]] = [:]
            for item in items where item.pathExtension == "strings" {
                let tableName = item.deletingPathExtension().lastPathComponent
                allTables.insert(tableName)
                tables[tableName] = try parseStringsFile(at: item)
            }
            tablesByLang[lang] = tables
        }

        let referenceLang = languages[0]
        for table in allTables.sorted() {
            guard let refDict = tablesByLang[referenceLang]?[table] else {
                issues.append(TableParityIssue(table: table, detail: "Missing \(table).strings in \(referenceLang).lproj"))
                continue
            }
            let refKeys = Set(refDict.keys)

            for lang in languages.dropFirst() {
                guard let candidate = tablesByLang[lang]?[table] else {
                    issues.append(TableParityIssue(table: table, detail: "Missing \(table).strings in \(lang).lproj"))
                    continue
                }
                let candKeys = Set(candidate.keys)
                let missing = refKeys.subtracting(candKeys).sorted()
                let extra = candKeys.subtracting(refKeys).sorted()
                if !missing.isEmpty {
                    issues.append(TableParityIssue(table: table, detail: "\(lang).lproj missing keys: \(missing.joined(separator: ", "))"))
                }
                if !extra.isEmpty {
                    issues.append(TableParityIssue(table: table, detail: "\(lang).lproj unexpected extra keys: \(extra.joined(separator: ", "))"))
                }
                for key in refKeys.intersection(candKeys).sorted() {
                    let refValue = refDict[key] ?? ""
                    let candValue = candidate[key] ?? ""
                    if refValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        candValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        issues.append(TableParityIssue(table: table, detail: "Empty value for key '\(key)'"))
                    }
                    let refSpecs = formatSpecifiers(in: refValue)
                    let candSpecs = formatSpecifiers(in: candValue)
                    if refSpecs != candSpecs {
                        issues.append(TableParityIssue(
                            table: table,
                            detail: "Format specifier mismatch for '\(key)' (\(referenceLang): \(refSpecs) vs \(lang): \(candSpecs))"
                        ))
                    }
                }
            }
        }
        return issues
    }
}
