// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

@testable import AxolotyMCP
import AxolotyInspectorRuntime
import AxolotyDiagnostics
import Foundation
import MCP
import Testing

@Test("Discover tool advertises and consumes an integer timeout")
func discoverToolTimeoutContract() throws {
    let schema = try #require(AxolotyMCPServer.discoverObjectsTool.inputSchema.objectValue)
    let properties = try #require(schema["properties"]?.objectValue)
    let timeoutSchema = try #require(properties["timeoutMilliseconds"]?.objectValue)

    #expect(timeoutSchema["type"]?.stringValue == "integer")

    let request = AxolotyMCPServer.makeDiscoveryRequest(from: ["timeoutMilliseconds": .int(1234)])
    #expect(request.timeoutMilliseconds == 1234)
}

@Test("Every MCP input schema is a valid object-root catalogue entry")
func objectInputSchemaCatalogueContract() throws {
    let expectedNames = [
        "axoloty_list_objects",
        "axoloty_get_object",
        "axoloty_discover_objects",
        "axoloty_decode_payload",
        "axoloty_server_status",
        "axoloty_get_diagnostics",
    ]
    let expectedPropertyTypes: [String: [String: String]] = [
        "axoloty_list_objects": [
            "coreType": "string",
            "objectType": "string",
            "objectId": "string",
            "sourceId": "string",
        ],
        "axoloty_get_object": ["objectId": "string"],
        "axoloty_discover_objects": [
            "coreType": "string",
            "objectType": "string",
            "objectId": "string",
            "timeoutMilliseconds": "integer",
        ],
        "axoloty_decode_payload": [
            "payload": "string",
            "encoding": "string",
            "payloadEncoding": "string",
            "format": "string",
        ],
        "axoloty_server_status": [:],
        "axoloty_get_diagnostics": [:],
    ]

    let tools = AxolotyMCPServer.objectInputSchemaTools
    #expect(tools.map(\.name) == expectedNames)

    for tool in tools {
        let schema = try #require(tool.inputSchema.objectValue)
        #expect(schema["type"]?.stringValue == "object")
        let propertyTypes = try #require(expectedPropertyTypes[tool.name])

        if propertyTypes.isEmpty {
            #expect(tool.name == "axoloty_server_status" || tool.name == "axoloty_get_diagnostics")
            #expect(!schema.keys.contains("properties"))
        } else {
            let properties = try #require(schema["properties"]?.objectValue)
            #expect(Set(properties.keys) == Set(propertyTypes.keys))

            for (propertyName, expectedType) in propertyTypes {
                let propertySchema = try #require(properties[propertyName]?.objectValue)
                #expect(propertySchema["type"]?.stringValue == expectedType)
                #expect(propertySchema["description"]?.stringValue != nil)
            }
        }

        if tool.name == "axoloty_get_object" {
            let required = try #require(schema["required"]?.arrayValue)
            #expect(required.compactMap { $0.stringValue } == ["objectId"])
        } else if tool.name == "axoloty_decode_payload" {
            let required = try #require(schema["required"]?.arrayValue)
            #expect(required.compactMap { $0.stringValue } == ["payload"])
        } else {
            #expect(!schema.keys.contains("required"))
        }
    }
}

@Test("Discover timeout retains its documented clamp")
func discoverToolTimeoutClamp() {
    let belowMinimum = AxolotyMCPServer.makeDiscoveryRequest(from: ["timeoutMilliseconds": .int(999)])
    let aboveMaximum = AxolotyMCPServer.makeDiscoveryRequest(from: ["timeoutMilliseconds": .int(30_001)])

    #expect(belowMinimum.timeoutMilliseconds == 1000)
    #expect(aboveMaximum.timeoutMilliseconds == 30_000)
}

@Test("Status reflects live online and offline communication state")
@MainActor
func statusReflectsInspectorTransportState() async throws {
    let session = StatusSession()
    let server = AxolotyMCPServer(session: session, namespace: "test")

    #expect((await server.collectStatus()).mqttConnected)

    session.state = .offline
    #expect(!(await server.collectStatus()).mqttConnected)
}

@MainActor
@Test("MCP diagnostics tool returns the shared versioned, redacted history")
func diagnosticsToolExportsRedactedHistory() async throws {
    let session = StatusSession()
    let revealingPolicy = DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: true)
    session.diagnostics.record(DiagnosticEvent(
        family: .presence,
        label: "presenceChanged",
        attributes: ["sourceID": "source-secret"],
        detail: "private runtime detail",
        provenance: DiagnosticProvenance(origin: .runtimeStream, runtimeSequence: 1, runtimeTimestampMS: 2),
        policy: revealingPolicy
    ))
    let mcpServer = AxolotyMCPServer(session: session, namespace: "test")
    let server = Server(
        name: "axoloty-mcp-diagnostics-test",
        version: "1.0.0",
        capabilities: .init(tools: .init())
    )
    await mcpServer.registerHandlers(on: server)
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

    do {
        try await server.start(transport: serverTransport)
        try await clientTransport.connect()
        let initialize = Initialize.request(
            id: 1,
            .init(
                protocolVersion: Version.latest,
                capabilities: .init(),
                clientInfo: .init(name: "diagnostics-test", version: "1.0")
            )
        )
        try await clientTransport.send(try JSONEncoder().encode(initialize))
        _ = try await receiveMCPMessage(from: clientTransport)

        let request = CallTool.request(
            id: 2,
            CallTool.Parameters(name: "axoloty_get_diagnostics", arguments: [:])
        )
        try await clientTransport.send(try JSONEncoder().encode(request))
        let response = try #require(JSONSerialization.jsonObject(
            with: try await receiveMCPMessage(from: clientTransport)
        ) as? [String: Any])
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == false)
        let content = try #require(result["content"] as? [[String: Any]])
        let json = try #require(content.first?["text"] as? String)
        #expect(!json.contains("source-secret"))
        #expect(!json.contains("private runtime detail"))
        let export = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(export["formatVersion"] as? Int == DiagnosticExport.currentVersion)
        #expect(export["revealsDetail"] as? Bool == false)
        #expect(export["revealsIdentities"] as? Bool == false)
    } catch {
        await server.stop()
        await clientTransport.disconnect()
        await serverTransport.disconnect()
        throw error
    }

    await server.stop()
    await clientTransport.disconnect()
    await serverTransport.disconnect()
}

@MainActor
@Test("In-memory MCP transport reports encoding failure and logs its cause")
func directTransportReportsEncodingFailureAndLogsCause() async throws {
    let session = StatusSession()
    let logCapture = EncodingLogCapture()
    let responseEncoder = AxolotyMCPServer.ResponseEncoder(
        status: { _ in throw ForcedEncodingError(operation: "status") }
    )
    let mcpServer = AxolotyMCPServer(
        session: session,
        namespace: "test",
        responseEncoder: responseEncoder,
        encodingFailureLogger: { message, metadata in
            logCapture.record(message: message, metadata: metadata)
        }
    )
    let server = Server(
        name: "axoloty-mcp-direct-test",
        version: "1.0.0",
        capabilities: .init(tools: .init())
    )
    await mcpServer.registerHandlers(on: server)
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

    do {
        try await server.start(transport: serverTransport)
        try await clientTransport.connect()

        let initializeRequest = Initialize.request(
            id: 1,
            .init(
                protocolVersion: Version.latest,
                capabilities: .init(),
                clientInfo: .init(name: "direct-test", version: "1.0")
            )
        )
        try await clientTransport.send(try JSONEncoder().encode(initializeRequest))
        _ = try await receiveMCPMessage(from: clientTransport)

        let callRequest = CallTool.request(
            id: 2,
            CallTool.Parameters(name: "axoloty_server_status", arguments: [:])
        )
        try await clientTransport.send(try JSONEncoder().encode(callRequest))
        let responseData = try await receiveMCPMessage(from: clientTransport)
        let envelope = try #require(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        let result = try #require(envelope["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "Unable to encode MCP response; please retry the request.")
        #expect(logCapture.message == "Failed to encode MCP response")
        #expect(logCapture.metadata?["operation"] == .string("axoloty_server_status"))
        if case let .string(errorChain)? = logCapture.metadata?["error"] {
            #expect(errorChain.contains("ForcedEncodingError"))
            #expect(errorChain.contains("forced status encoding failure"))
        } else {
            Issue.record("expected wrapped encoding error metadata")
        }
    } catch {
        await server.stop()
        await clientTransport.disconnect()
        await serverTransport.disconnect()
        throw error
    }

    await server.stop()
    await clientTransport.disconnect()
    await serverTransport.disconnect()
}

@Test("Test deadlines do not join cancellation-resistant operations")
func deadlineDoesNotJoinCancellationResistantOperation() async throws {
    let gate = CancellationResistantGate()
    let operation = Task {
        do {
            try await withDeadline(
                "hostile cancellation-resistant operation",
                timeout: .milliseconds(20),
                recordTimeout: false
            ) {
                await gate.wait()
            }
            return false
        } catch is TestDeadlineExceeded {
            return true
        }
    }

    try await waitForCondition("hostile operation entry") {
        await gate.entered
    }
    #expect(try await operation.value)
    await gate.release()
}

@Test("Deadline result boxes accept only their first resolution")
func deadlineResultBoxAcceptsOnlyFirstResolution() async {
    let box = DeadlineResultBox<String>()
    let first = await withCheckedContinuation { (continuation: CheckedContinuation<Result<String, Error>, Never>) in
        box.install(continuation)
        box.resolve(.success("first"))
        box.resolve(.success("second"))
    }
    let second = await withCheckedContinuation { (continuation: CheckedContinuation<Result<String, Error>, Never>) in
        box.install(continuation)
    }

    #expect((try? first.get()) == "first")
    #expect((try? second.get()) == "first")
}

@Test("MCP server forwards broker readiness timeout to inspector runtime")
func brokerConnectionTimeoutIsApplied() {
    let configuration = AxolotyMCPServer.makeConnectionConfiguration(
        host: "broker.local",
        port: 1883,
        namespace: "test",
        connectTimeout: .seconds(37)
    )

    #expect(configuration.connectTimeout == .seconds(37))
}

@MainActor
@Test("Stdio start serves requests until the transport closes")
func stdioStartReturnsOnlyAfterTransportCloses() async throws {
    let mcpServer = AxolotyMCPServer(session: StatusSession(), namespace: "test")
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    let completed = CompletionFlag()
    let serving = Task { @MainActor in
        try await mcpServer.startStdio(transport: serverTransport)
        await completed.set()
    }

    // Let the server bind its side of the pair before the client sends.
    try await Task.sleep(for: .milliseconds(500))
    try await clientTransport.connect()
    let initialize = Initialize.request(
        id: 1,
        .init(
            protocolVersion: Version.latest,
            capabilities: .init(),
            clientInfo: .init(name: "stdio-lifetime-test", version: "1.0")
        )
    )
    try await clientTransport.send(try JSONEncoder().encode(initialize))
    _ = try await receiveMCPMessage(from: clientTransport)

    // The server answered, so it is running. It must still be serving now:
    // returning early made `axoloty-mcp --transport stdio` exit with status 0
    // before the first request.
    try await Task.sleep(for: .milliseconds(200))
    #expect(await !completed.value)

    // Closing the client side ends the transport and lets the call return.
    await clientTransport.disconnect()
    await serverTransport.disconnect()
    let deadline = ContinuousClock.now + .seconds(10)
    while await !completed.value, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(await completed.value)
    serving.cancel()
}

private actor CompletionFlag {
    private(set) var value = false
    func set() { value = true }
}
