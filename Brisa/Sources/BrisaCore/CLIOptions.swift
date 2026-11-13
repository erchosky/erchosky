import Foundation

public struct CLIOptions: Sendable {
    public let command: String
    public let arguments: [String]
    public let json: Bool
    public let launch: Bool
    public static let commands: Set<String> = ["status", "categories", "orphans", "worktrees", "diagnostics", "spacemap", "agents", "setup", "analyse", "findings", "select", "clean", "free", "quit", "journal", "undo", "protect", "unprotect", "protected", "keep-process", "routine", "alerts", "update", "settings", "open", "help", "version"]
    public static let validCategories: Set<String> = Set(["cache", "log", "other", "eligible", "inventory", "all"] + StorageCategory.allCases.map(\.rawValue))
    public init(_ input: [String]) throws {
        let parsed = Self.splitGlobalOptions(input)
        json = parsed.json; launch = parsed.launch
        let args = parsed.arguments
        command = args.first ?? "help"
        arguments = Array(args.dropFirst())
        guard Self.commands.contains(command) else { throw BrisaError.invalid("Unknown command: \(command)") }
        if ["status", "orphans", "worktrees", "diagnostics", "spacemap", "agents", "setup", "analyse", "free", "quit", "clean", "journal", "protected", "routine", "update", "settings", "open", "help", "version"].contains(command), !arguments.isEmpty {
            throw BrisaError.invalid("\(command) takes no positional arguments")
        }
        if ["undo", "protect", "unprotect", "keep-process", "alerts"].contains(command), arguments.count != 1 {
            throw BrisaError.invalid("\(command) requires exactly one argument")
        }
        if command == "alerts", !["status", "on", "off"].contains(arguments.first ?? "") { throw BrisaError.invalid("alerts status|on|off") }
        if command == "select", arguments.isEmpty { throw BrisaError.invalid("select <file-id...>|none") }
        if command == "categories", !arguments.isEmpty {
            guard arguments.count == 2, arguments[0] == "--category",
                  StorageCategory(rawValue: arguments[1]) != nil else {
                throw BrisaError.invalid("categories [--category <storage-category>]")
            }
        }
        if command == "findings" { try Self.validateFindingsArguments(arguments) }
    }

    /// A search value can itself be "--json" or "--no-launch".
    /// Only tokens outside a value position are global options.
    public static func splitGlobalOptions(_ input: [String]) -> (arguments: [String], json: Bool, launch: Bool) {
        var arguments: [String] = [], json = false, launch = true, expectsValue = false
        for token in input {
            if expectsValue {
                arguments.append(token)
                expectsValue = false
            } else if token == "--json" { json = true }
            else if token == "--no-launch" { launch = false }
            else {
                arguments.append(token)
                expectsValue = ["--search", "--category", "--limit"].contains(token)
            }
        }
        return (arguments, json, launch)
    }

    public static func validateFindingsArguments(_ arguments: [String]) throws {
        var seen = Set<String>()
        var i = 0
        while i < arguments.count {
            let flag = arguments[i]
            guard ["--search", "--category", "--limit"].contains(flag), i + 1 < arguments.count,
                  seen.insert(flag).inserted else {
                throw BrisaError.invalid("findings [--search text] [--category <category>|eligible|inventory] [--limit 1…500]")
            }
            if flag == "--category", !Self.validCategories.contains(arguments[i + 1]) { throw BrisaError.invalid("Invalid category") }
            if flag == "--limit", !(Int(arguments[i + 1]).map { (1...500).contains($0) } ?? false) { throw BrisaError.invalid("Invalid limit") }
            i += 2
        }
    }

    public static let help = """
    Brisa 0.1.0 · macOS resource monitor
    Usage: brisa <command> [arguments] [--json] [--no-launch]
      status                       Measured resource and 11-category index status
      categories [--category id]   Measured breakdown across all 11 storage categories
      orphans                      Read-only build metadata assessments
      worktrees                    Read-only Git worktree and artifact inspection
      diagnostics                  System diagnostics; no cleanup
      spacemap                     Proportional allocated-byte map of the inventory
      analyse                      Start a bounded scan across all 11 categories (poll status for completion)
      findings [--search text] [--category vm_containers|app_caches|package_caches|developer_caches|editor_extensions|toolchains_sdks|agent_editor_history|temporary_files|logs_crashes|app_leftovers|downloads_installers|eligible|inventory|cache|log|other] [--limit 1…500]
      select <id...>|none           Reviewable selection, maximum 100
      clean / free                 Native confirmation for the current selection
      journal                      Verified operation journal
      undo <journal-id>            Native confirmation; restore only if possible
      protect <absolute-path>      Add a protected path
      unprotect <absolute-path>    Native confirmation to remove user protection
      protected                    List user protections
      keep-process <pid>           Record a protected PID (process termination is disabled)
      agents                       Local CLI discovery; no authentication claims
      setup / settings / open      Open the native app
      alerts status|on|off          Notification status or explicit permission flow
      routine / update             Availability and documented limitations
      quit                         Quit app; refused while an operation is active
      help / version
    All errors are valid JSON with --json. No --yes or headless destructive mode.
    """
}
