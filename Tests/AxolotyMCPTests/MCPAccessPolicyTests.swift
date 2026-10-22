// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyInspectorCore
import AxolotyDiagnostics
@testable import AxolotyMCP
import Testing

private let full = InspectorObject(
    objectId: "o", coreType: "Task", objectType: "t", name: "n", sourceId: "s",
    payload: "{\"secret\":1}", privateData: "p"
)

@Test("The default policy is read-only")
func defaultPolicyIsReadOnly() {
    let policy = MCPAccessPolicy.localReadOnly
    for tool in MCPAccessPolicy.readTools { #expect(policy.allows(tool: tool)) }
    for tool in MCPAccessPolicy.controlTools { #expect(!policy.allows(tool: tool)) }
    #expect(!policy.allows(tool: "unknown"))
}

@Test("Local controls require explicit enablement")
func localControlsNeedEnablement() {
    let policy = MCPAccessPolicy(scope: .local, controlsEnabled: true)
    #expect(policy.allows(tool: "axoloty_discover_objects"))
}

@Test("Remote scope never exposes controls or payloads")
func remoteIsAlwaysReadOnly() {
    let policy = MCPAccessPolicy(scope: .remote, controlsEnabled: true, includePayloads: true)
    #expect(!policy.allows(tool: "axoloty_discover_objects"))
    #expect(policy.redact(full).payload == nil)
    #expect(policy.redact(full).privateData == nil)
}

@Test("Every advertised tool is classified as read or control")
func everyToolIsClassified() {
    let advertised = Set(AxolotyMCPServer.objectInputSchemaTools.map(\.name))
    #expect(advertised == MCPAccessPolicy.readTools.union(MCPAccessPolicy.controlTools))
}

@Test("MCP diagnostic exports always redact details and identities")
func diagnosticExportIsRedactedForMCP() throws {
    let revealing = DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: true)
    let event = DiagnosticEvent(
        family: .presence,
        label: "presenceChanged",
        attributes: ["sourceID": "source-secret"],
        detail: "private detail",
        provenance: DiagnosticProvenance(origin: .runtimeStream, runtimeSequence: 1, runtimeTimestampMS: 2),
        policy: revealing
    )
    var history = DiagnosticHistory(capacity: 2)
    history.record(event)

    let json = try AxolotyMCPServer.encodeDiagnostics(history)

    #expect(!json.contains("source-secret"))
    #expect(!json.contains("private detail"))
    #expect(json.contains(DiagnosticRedactionPolicy.marker))
}

@Test("Payloads and private data are redacted by default")
func redactsByDefault() {
    let redacted = MCPAccessPolicy.localReadOnly.redact(full)
    #expect(redacted.payload == nil && redacted.privateData == nil)
    #expect(redacted.objectId == "o" && redacted.name == "n")
}

@Test("Payloads are included only when a local operator allows them")
func localOperatorMayIncludePayloads() {
    let policy = MCPAccessPolicy(scope: .local, includePayloads: true)
    #expect(policy.redact(full) == full)
}
