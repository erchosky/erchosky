import XCTest
@testable import BrisaCore

final class ProtocolTests: XCTestCase {
    func testWireDatesUseISO8601() throws {
        let value = try JSONValue.encode(MetricsSampler().sample())
        let date = try XCTUnwrap(value.object?["date"]?.string)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: date))
    }
    func testJSONRoundTripAndErrorEnvelope() throws {
        let data = try JSONEncoder().encode(IPCResponse(id: "local", error: BrisaError.rejected("Open file")))
        let response = try JSONDecoder().decode(IPCResponse.self, from: data)
        XCTAssertFalse(response.ok); XCTAssertNil(response.result); XCTAssertEqual(response.error?.code, "safety_rejected")
        let value = JSONValue.object(["message": .string("line\n\"quote\""), "array": .array([.number(42), .null, .bool(true)])])
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
    func testCLIOptionsAndFilters() throws {
        let options = try CLIOptions(["findings", "--category", "eligible", "--search", "cache", "--limit", "20", "--json", "--no-launch"])
        XCTAssertTrue(options.json); XCTAssertFalse(options.launch); XCTAssertEqual(options.command, "findings")
        XCTAssertEqual(options.arguments.count, 6)
        XCTAssertEqual(try CLIOptions([]).command, "help")
    }
    func testCLIRejectsUnknownFlagsCommandsAndBadArguments() {
        for input in [["delete"], ["clean", "--yes"], ["protect"], ["undo", "a", "b"], ["findings", "--search"], ["findings", "--limit", "0"], ["findings", "--category", "secret"], ["alerts", "maybe"], ["select"]] {
            XCTAssertThrowsError(try CLIOptions(input), input.description)
        }
    }
    func testRequestValidation() throws {
        XCTAssertNoThrow(try IPCRequest(command: "status").validate())
        XCTAssertThrowsError(try IPCRequest(command: "status", version: 2).validate())
        XCTAssertThrowsError(try IPCRequest(command: "status", id: "not-uuid").validate())
        XCTAssertThrowsError(try IPCRequest(command: "protect", arguments: ["x\0"]).validate())
        XCTAssertThrowsError(try IPCRequest(command: "protect", arguments: [String(repeating: "a", count: 8193)]).validate())
    }
    func testIPCRealSocketSameUIDAndPermissions() throws {
        let f = try Fixture(), path = f.home.appendingPathComponent("ipc/control.sock").path
        let server = IPCServer(path: path)
        try server.start { request in IPCResponse(id: request.id, result: .string(request.command)) }
        defer { server.stop() }
        let response = try IPCClient.call(IPCRequest(command: "status"), path: path, timeout: 2)
        XCTAssertEqual(response.result, .string("status"))
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let duplicate = IPCServer(path: path)
        XCTAssertThrowsError(try duplicate.start { IPCResponse(id: $0.id, result: .bool(true)) })
    }
    func testIPCRejectsPermissiveDirectory() throws {
        let f = try Fixture(), directory = f.home.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        let server = IPCServer(path: directory.appendingPathComponent("control.sock").path)
        XCTAssertThrowsError(try server.start { IPCResponse(id: $0.id, result: .bool(true)) })
    }
    func testMCPHandshakeAndToolSurface() throws {
        var commands: [String] = []
        let service = MCPService { request in commands.append(request.command); return IPCResponse(id: request.id, result: .bool(true)) }
        XCTAssertNotNil(service.respond(request("tools/list"))?.object?["error"])
        initialize(service)
        let response = service.respond(request("tools/list"))
        XCTAssertEqual(response?.object?["result"]?.object?["tools"]?.array?.count, 9)
        for name in ["clean", "delete", "quit", "select", "settings", "terminate_process"] {
            XCTAssertNotNil(service.respond(call(name))?.object?["error"])
        }
        _ = service.respond(call("index_summary")); XCTAssertEqual(commands, ["mcp.summary"])
    }
    func testMCPRejectsPathInjectionAndUnknownSchemaFields() throws {
        var commands: [String] = []
        let service = MCPService { request in commands.append(request.command); return IPCResponse(id: request.id, result: .bool(true)) }
        initialize(service)
        XCTAssertNotNil(service.respond(call("file_info", args: ["path": .string("/etc/passwd")]))?.object?["error"])
        XCTAssertNotNil(service.respond(call("file_info", args: ["fileID": .string("id"), "command": .string("rm")]))?.object?["error"])
        XCTAssertNotNil(service.respond(call("submit_conclusions", args: ["conclusions": .array([.object(["fileID": .string("x"), "delete": .bool(true)])])]))?.object?["error"])
        XCTAssertTrue(commands.isEmpty)
    }
    func testMCPBindsDataOnlyAndLimitsCalls() {
        var commands: [String] = []
        let service = MCPService { request in commands.append(request.command); return IPCResponse(id: request.id, result: .bool(true)) }
        initialize(service)
        for _ in 0..<120 { _ = service.respond(call("index_summary")) }
        XCTAssertNotNil(service.respond(call("index_summary"))?.object?["error"])
        XCTAssertEqual(commands.count, 120)
        XCTAssertNil(service.respond(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/cancelled")])))
    }
    private func request(_ method: String, params: [String: JSONValue] = [:]) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": .number(1), "method": .string(method), "params": .object(params)])
    }
    private func call(_ name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        request("tools/call", params: ["name": .string(name), "arguments": .object(args)])
    }
    private func initialize(_ service: MCPService) {
        _ = service.respond(request("initialize", params: ["protocolVersion": .string("2025-11-25"), "capabilities": .object([:]), "clientInfo": .object(["name": .string("test"), "version": .string("1")])]))
        _ = service.respond(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
    }
}
