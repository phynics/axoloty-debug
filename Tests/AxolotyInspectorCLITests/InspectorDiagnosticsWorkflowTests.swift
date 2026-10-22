// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyDiagnostics
import AxolotyInspectorCore
import AxolotyInspectorRuntime
import Foundation
import Testing

@Test("Diagnostics command configures redaction and writes a versioned export")
@MainActor
func diagnosticsCommandExportsSharedHistory() async throws {
    let session = FakeInspectorSession()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("axoloty-diagnostic-command-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let policy = DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: true)
    let configuration = InspectorConfiguration(
        command: .diagnostics(DiagnosticsCommand(
            duration: InspectorDuration(value: .milliseconds(1)),
            captureDirectory: directory.path,
            revealDetail: true,
            revealIdentities: true
        )),
        connection: InspectorConnectionConfiguration(host: "broker", port: 1883, namespace: "test"),
        output: .json
    )
    var output: [String] = []
    var diagnostics: [String] = []

    let app = InspectorDiagnosticsApplication(
        configuration: configuration,
        session: session,
        writeOutput: { output.append($0) },
        writeDiagnostic: { diagnostics.append($0) }
    )
    let result = await app.run()

    #expect(result == nil)
    #expect(session.connected)
    #expect(session.configuredDiagnosticPolicy == policy)
    #expect(session.configuredCapture?.directory == directory)
    #expect(diagnostics.isEmpty)
    let json = try #require(output.first)
    let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    #expect(object["formatVersion"] as? Int == DiagnosticExport.currentVersion)
    #expect(object["revealsDetail"] as? Bool == true)
    #expect(object["revealsIdentities"] as? Bool == true)
}
