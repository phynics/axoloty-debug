// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

@testable import AxolotyDiagnostics
import Foundation
import Testing

private func event(
    sequence: UInt64,
    detail: String = "secret",
    attributes: [String: String] = [:],
    policy: DiagnosticRedactionPolicy = .redactAll
) -> DiagnosticEvent {
    DiagnosticEvent(
        family: .request,
        label: "requestAccepted",
        attributes: attributes,
        detail: detail,
        provenance: DiagnosticProvenance(origin: .runtimeStream, runtimeSequence: sequence, runtimeTimestampMS: 1),
        policy: policy
    )
}

@Test("Detail and identities are redacted by default")
func redactsByDefault() {
    let value = event(sequence: 1, attributes: ["objectID": "abcd", "outcome": "accepted"])
    #expect(value.detail == DiagnosticRedactionPolicy.marker)
    #expect(value.attributes["objectID"] == DiagnosticRedactionPolicy.marker)
    #expect(value.attributes["outcome"] == "accepted")
}

@Test("Revealing detail and identities is explicit")
func revealsWhenAsked() {
    let policy = DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: true)
    let value = event(sequence: 1, attributes: ["objectID": "abcd"], policy: policy)
    #expect(value.detail == "secret")
    #expect(value.attributes["objectID"] == "abcd")
}

@Test("History stays bounded and reports overflow")
func historyBoundedWithOverflow() {
    var history = DiagnosticHistory(capacity: 2)
    for sequence in 1...4 { history.record(event(sequence: UInt64(sequence))) }
    #expect(history.events.count == 2)
    #expect(history.events.first?.provenance.runtimeSequence == 3)
    #expect(history.evictedCount == 2)
    #expect(history.uncertainty == [.historyOverflow])
}

@Test("Sequence gaps are reported as loss")
func sequenceGapReported() {
    var history = DiagnosticHistory(capacity: 10)
    history.record(event(sequence: 1))
    history.record(event(sequence: 5))
    #expect(history.lostRuntimeValues == 3)
    #expect(history.uncertainty == [.sequenceGap])
}

@Test("Runtime stream loss and presence uncertainty are surfaced")
func runtimeStateSurfaced() {
    var history = DiagnosticHistory(capacity: 10)
    #expect(history.uncertainty.isEmpty)
    history.recordRuntimeState(streamDropped: 2, presenceUncertain: true)
    #expect(history.uncertainty == [.runtimeStreamLoss, .presenceUncertain])
    #expect(history.lostRuntimeValues == 2)
}

@Test("Rolling capture is bounded by file count and size")
func captureRolls() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("axoloty-capture-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try DiagnosticCapture(
        configuration: DiagnosticCaptureConfiguration(directory: directory, maximumFileBytes: 1024, maximumFiles: 2)
    )
    for sequence in 1...50 { try capture.append(event(sequence: UInt64(sequence))) }
    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(files.count <= 2)
    #expect(!files.isEmpty)
}

@Test("Nothing is written without an explicit capture")
func noImplicitCapture() {
    var history = DiagnosticHistory(capacity: 1)
    history.record(event(sequence: 1))
    #expect(history.events.count == 1)
}
