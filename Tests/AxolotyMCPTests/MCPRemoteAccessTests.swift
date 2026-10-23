// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

@testable import AxolotyMCP
import Foundation
import MCP
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Test("A non-loopback HTTP listener requires independent access protection")
func nonLoopbackListenerRequiresAccessProtection() async {
    let server = MCPHTTPServer(
        host: "0.0.0.0",
        port: 0,
        validationPipeline: StandardValidationPipeline(validators: []),
        serverFactory: { _, transport in
            let server = Server(
                name: "axoloty-mcp-remote-policy-test",
                version: "1.0.0",
                capabilities: .init()
            )
            try await server.start(transport: transport)
            return server
        }
    )

    do {
        try await server.start()
        Issue.record("non-loopback listener started without independent access protection")
    } catch {
        #expect(String(reflecting: error).contains("accessProtection"))
    }
}

@MainActor
@Test("Remote HTTP sessions require a bearer token and never expose controls")
func remoteHTTPSessionsRequireTokenAndRejectControls() async throws {
    let token = "remote-test-token"
    let protection = try #require(MCPAccessProtection(bearerToken: token))
    let session = StatusSession()
    let mcpServer = AxolotyMCPServer(session: session, namespace: "test")
    let httpServer = MCPHTTPServer(
        host: "0.0.0.0",
        port: 0,
        accessProtection: protection,
        serverFactory: { _, transport in
            let server = Server(
                name: "axoloty-mcp-remote-policy-test",
                version: "1.0.0",
                capabilities: .init(
                    resources: .init(subscribe: false, listChanged: false),
                    tools: .init(listChanged: false)
                )
            )
            await mcpServer.registerHandlers(
                on: server,
                policy: MCPAccessPolicy(scope: .remote)
            )
            try await server.start(transport: transport)
            return server
        }
    )

    let startTask = try await startHTTPServer(httpServer, phase: "remote access server start")
    let port = try #require(await httpServer.listeningPort())
    let initializeBody = try #require(try makeInitializeRequest().body)

    do {
        let (_, missingToken) = try await sendHTTPBody(to: port, body: initializeBody)
        #expect(missingToken.statusCode == 401)
        #expect(missingToken.value(forHTTPHeaderField: "WWW-Authenticate") == "Bearer")

        let (_, wrongToken) = try await sendHTTPBody(
            to: port,
            body: initializeBody,
            bearerToken: "wrong-token"
        )
        #expect(wrongToken.statusCode == 401)

        let (initializeData, authenticated) = try await sendHTTPBody(
            to: port,
            body: initializeBody,
            bearerToken: token
        )
        #expect(authenticated.statusCode == 200)
        #expect(authenticated.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
        let sessionID = try #require(authenticated.value(forHTTPHeaderField: "Mcp-Session-Id"))
        try requireResponseBody(initializeData, response: authenticated, operation: "initialize")
        let initializeMessage = try jsonMessage(from: initializeData)
        let initializeResult = try #require(initializeMessage["result"] as? [String: Any])
        #expect(initializeResult["protocolVersion"] as? String == "2025-11-25")

        let listBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": [:] as [String: Any],
        ])
        let (listData, listResponse) = try await sendHTTPBody(
            to: port,
            body: listBody,
            sessionID: sessionID,
            bearerToken: token
        )
        #expect(listResponse.statusCode == 200)
        try requireResponseBody(listData, response: listResponse, operation: "tools/list")
        let listMessage = try jsonMessage(from: listData)
        let listResult = try #require(listMessage["result"] as? [String: Any])
        let tools = try #require(listResult["tools"] as? [[String: Any]])
        let toolNames = tools.compactMap { $0["name"] as? String }
        #expect(!toolNames.contains("axoloty_discover_objects"))
        #expect(toolNames.contains("axoloty_list_objects"))

        let callBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": [
                "name": "axoloty_discover_objects",
                "arguments": ["objectId": "remote-object"],
            ] as [String: Any],
        ])
        let (callData, callResponse) = try await sendHTTPBody(
            to: port,
            body: callBody,
            sessionID: sessionID,
            bearerToken: token
        )
        #expect(callResponse.statusCode == 200)
        try requireResponseBody(callData, response: callResponse, operation: "tools/call")
        let callMessage = try jsonMessage(from: callData)
        let callResult = try #require(callMessage["result"] as? [String: Any])
        #expect(callResult["isError"] as? Bool == true)
        let content = try #require(callResult["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        #expect(text.contains("Tool not available under the current access policy"))
    } catch {
        try? await stopHTTPServer(
            httpServer,
            startTask: startTask,
            phase: "remote access cleanup"
        )
        throw error
    }

    try await stopHTTPServer(
        httpServer,
        startTask: startTask,
        phase: "remote access shutdown"
    )
}

private func requireResponseBody(
    _ data: Data,
    response: HTTPURLResponse,
    operation: String
) throws {
    let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "missing"
    let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") ?? "missing"
    let message = "\(operation) response was empty: status=\(response.statusCode), contentType=\(contentType), session=\(sessionID)"
    try #require(!data.isEmpty, message)
}

private func jsonMessage(from data: Data) throws -> [String: Any] {
    let text = String(decoding: data, as: UTF8.self)
    let payload: String
    if let line = text.split(separator: "\n").first(where: { line in
        guard line.hasPrefix("data:") else { return false }
        return !line.dropFirst("data:".count).allSatisfy(\.isWhitespace)
    }) {
        payload = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
    } else {
        payload = text
    }
    return try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
}
