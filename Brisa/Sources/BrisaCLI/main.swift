import Foundation
import AppKit
import BrisaCore

func output(_ response: IPCResponse, json: Bool) {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if json {
        if let data = try? encoder.encode(response) { print(String(decoding: data, as: UTF8.self)) }
    } else if response.ok, let result = response.result, let data = try? encoder.encode(result) {
        print(String(decoding: data, as: UTF8.self))
    } else { fputs((response.error?.message ?? "Unknown error") + "\n", stderr) }
}

let input = Array(CommandLine.arguments.dropFirst())
do {
    let options = try CLIOptions(input)
    if options.command == "help" {
        if options.json { output(IPCResponse(id: "local", result: .string(CLIOptions.help)), json: true) }
        else { print(CLIOptions.help) }; exit(0)
    }
    if options.command == "version" {
        output(IPCResponse(id: "local", result: .object(["version": .string("0.1.0"), "protocol": .number(1)])), json: options.json); exit(0)
    }
    let request = IPCRequest(command: options.command, arguments: options.arguments)
    // Native confirmation may remain open for 90 seconds. The client must not time out first.
    let timeout: Int = ["clean", "free", "undo", "unprotect"].contains(options.command) ? 120 : 15
    var response: IPCResponse
    do { response = try IPCClient.call(request, timeout: timeout) }
    catch {
        // Retry only before a request was delivered. Never repeat a potentially confirmed mutation.
        guard options.launch, !FileManager.default.fileExists(atPath: IPCSocket.path) else { throw error }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let localBundle = executable.deletingLastPathComponent().appendingPathComponent("Brisa.app")
        let bundle = FileManager.default.fileExists(atPath: localBundle.path) ? localBundle.path : "/Applications/Brisa.app"
        guard FileManager.default.fileExists(atPath: bundle) else {
            throw BrisaError.unavailable("App not running. Build with scripts/package.sh and open dist/Brisa.app")
        }
        let launch = try CommandRunner.run("/usr/bin/open", [bundle])
        guard launch.status == 0 else { throw BrisaError.unavailable("Could not launch Brisa") }
        var ready = false
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: IPCSocket.path) { ready = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard ready else { throw BrisaError.unavailable("Brisa did not become ready within 5 seconds") }
        response = try IPCClient.call(request, timeout: timeout)
    }
    output(response, json: options.json)
    exit(response.ok ? 0 : (response.error?.code == "safety_rejected" ? 3 : 1))
} catch {
    output(IPCResponse(id: "local", error: error), json: CLIOptions.splitGlobalOptions(input).json)
    exit((error as? BrisaError)?.code == "invalid_request" ? 2 : 1)
}
