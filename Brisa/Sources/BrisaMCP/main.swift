import Foundation
import BrisaCore

// Newline-delimited stdio JSON-RPC. Never log to stdout except protocol messages.
let service = MCPService()
var pending = Data()
func emit(_ value: JSONValue) {
    if var data = try? JSONEncoder().encode(value) { data.append(10); FileHandle.standardOutput.write(data) }
}
while true {
    let chunk = FileHandle.standardInput.availableData
    if chunk.isEmpty { break }
    pending.append(chunk)
    while let newline = pending.firstIndex(of: 10) {
        let line = Data(pending.prefix(upTo: newline)); pending.removeSubrange(...newline)
        guard line.count <= 65_536 else { fputs("Input frame budget exceeded\n", stderr); exit(2) }
        do {
            let input = try JSONDecoder().decode(JSONValue.self, from: line)
            if let response = service.respond(input) { emit(response) }
        } catch {
            emit(.object(["jsonrpc": .string("2.0"), "id": .null, "error": .object(["code": .number(-32700), "message": .string("Parse error")])]))
        }
    }
    guard pending.count <= 65_536 else { fputs("Input frame budget exceeded\n", stderr); exit(2) }
}
if !pending.isEmpty { fputs("Incomplete JSON-RPC frame\n", stderr); exit(2) }
