// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Axoloty
import AxolotyDiagnostics
import AxolotyInspectorCore
import AxolotyProtocol
import AxolotyWire
import Foundation
import Testing

@testable import AxolotyInspectorRuntime

/// A transport that accepts everything, reaches no network, and lets the test
/// inject inbound frames.
private actor InjectingTransport: AxolotyRuntimeTransport {
    nonisolated let capabilities: RuntimeTransportCapabilities = []
    private var receive: (@Sendable (RuntimeInboundFrame) -> Void)?

    func start(
        receive: @escaping @Sendable (RuntimeInboundFrame) -> Void,
        lastWill: RuntimeTransportLastWill?
    ) async throws(AxolotyError) {
        self.receive = receive
    }

    func setFailureHandler(_ handler: @escaping @Sendable (RuntimeTransportFailure) -> Void) async {}
    func perform(_ effect: RuntimeTransportEffect) async throws(AxolotyError) {}
    func stop() async { receive = nil }
    func deliver(_ frame: RuntimeInboundFrame) { receive?(frame) }
}

/// Smoke test for the diagnostic contract this package consumes from Core.
///
/// Core's public-consumer evidence (`TransportSPIConsumer`) proves that Core's
/// own diagnostics API behaves. It does not run Debug code. This test drives
/// the real Core `AxolotyRuntime` through `AxolotyInspectorSession` and checks
/// the parts of `RuntimeDiagnostic`, `RuntimeDiagnostics`, and
/// `RuntimeCapabilityInformation` that the adapter reads: snapshot attributes,
/// stream provenance, typed observations, and default redaction. A Core change
/// that renames or drops one of them fails here instead of in the field.
@Test @MainActor
func sessionConsumesCoreRuntimeDiagnosticsAndRedactsByDefault() async throws {
    let transport = InjectingTransport()
    let session = try AxolotyInspectorSession(
        configuration: InspectorConnectionConfiguration(host: "unused.invalid", port: 1883, namespace: "test")
    ) { _ in transport }
    try await session.connect()

    let sourceID = "0a1b2c3d-4e5f-4061-8293-a4b5c6d7e8f9"
    let objectID = "33333333-3333-4333-8333-333333333333"
    await transport.deliver(.profile(
        route: "coaty/3/test/ADV:CoatyObject/\(sourceID)",
        payload: Array(#"{"object":{"objectId":"\#(objectID)","coreType":"CoatyObject","objectType":"com.coaty.test.WireFixture","name":"wire-fixture"}}"#.utf8),
        nowMS: 1
    ))
    await transport.deliver(.profile(
        route: "coaty/3/test/DAD:CoatyObject/\(sourceID)",
        payload: Array(#"{"objectIds":["\#(objectID)"]}"#.utf8),
        nowMS: 2
    ))

    func streamPresence(_ history: DiagnosticHistory) -> [DiagnosticEvent] {
        history.events.filter { $0.family == .presence && $0.provenance.origin == .runtimeStream }
    }
    var history = await session.diagnosticHistory()
    for _ in 0..<500 where streamPresence(history).count < 2 {
        try await Task.sleep(for: .milliseconds(10))
        history = await session.diagnosticHistory()
    }
    await session.stop()
    history = await session.diagnosticHistory()

    // Snapshot events carry the lifecycle and capability fields the adapter reads.
    let lifecycle = try #require(history.events.first { $0.label == "lifecycleSnapshot" })
    #expect(lifecycle.family == .lifecycle)
    #expect(["from", "to", "state", "transportEpoch"].allSatisfy { lifecycle.attributes[$0] != nil })
    let capabilities = try #require(history.events.first { $0.label == "capabilitiesSnapshot" })
    #expect(capabilities.family == .capabilities)
    #expect([
        "protocolCapabilities", "wireProfile", "maximumPayloadBytes",
        "maximumObjects", "maximumPendingCorrelations", "diagnosticCapacity",
    ].allSatisfy { capabilities.attributes[$0] != nil })

    // Advertise then Deadvertise yield typed, sequenced presence observations.
    let presence = streamPresence(history)
    try #require(presence.count == 2, "saw \(history.events.map(\.label))")
    #expect(presence[0].attributes["evidence"] == "peerAdvertisement")
    #expect(presence[0].attributes["activeObjects"] == "1")
    #expect(presence[1].attributes["activeObjects"] == "0")
    #expect(presence[0].provenance.runtimeSequence > 0)
    #expect(presence[1].provenance.runtimeSequence > presence[0].provenance.runtimeSequence)

    // Default redaction hides identities and free-form detail end to end.
    let export = try JSONEncoder().encode(DiagnosticExport(history: history))
    let text = String(decoding: export, as: UTF8.self)
    #expect(!text.contains(sourceID))
    #expect(!text.contains(objectID))
    #expect(presence[0].attributes["objectID"] == DiagnosticRedactionPolicy.marker)
    #expect(presence[0].attributes["sourceID"] == DiagnosticRedactionPolicy.marker)
}
