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

@Test("Sequence tracking remains defined at UInt64 boundaries and out-of-order input")
func sequenceBoundaryHandled() {
    var history = DiagnosticHistory(capacity: 10)
    history.record(event(sequence: UInt64.max - 1))
    history.record(event(sequence: UInt64.max))
    history.record(event(sequence: 2))
    #expect(history.lostRuntimeValues == 0)
    #expect(history.uncertainty == [.sequenceRegression])

    var saturated = DiagnosticHistory(capacity: 10)
    saturated.record(event(sequence: 1))
    saturated.recordRuntimeState(streamDropped: .max, presenceUncertain: false)
    saturated.record(event(sequence: 3))
    #expect(saturated.lostRuntimeValues == .max)
}

@Test("Re-redaction keeps history completeness and cannot recover secret fields")
func historyCanBeRedactedAgain() {
    let revealing = DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: true)
    var history = DiagnosticHistory(capacity: 2)
    history.record(event(
        sequence: 1,
        attributes: ["sourceID": "source-secret"],
        policy: revealing
    ))
    history.recordRuntimeState(streamDropped: 2, presenceUncertain: true)

    let redacted = history.redacted()
    #expect(history.events[0].attributes["sourceID"] == "source-secret")
    #expect(redacted.events[0].attributes["sourceID"] == DiagnosticRedactionPolicy.marker)
    #expect(redacted.events[0].detail == DiagnosticRedactionPolicy.marker)
    #expect(redacted.uncertainty == history.uncertainty)
    #expect(redacted.lostRuntimeValues == history.lostRuntimeValues)
}

@Test("Runtime stream loss and presence uncertainty are surfaced")
func runtimeStateSurfaced() {
    var history = DiagnosticHistory(capacity: 10)
    #expect(history.uncertainty.isEmpty)
    history.recordRuntimeState(streamDropped: 2, presenceUncertain: true)
    #expect(history.uncertainty == [.runtimeStreamLoss, .presenceUncertain])
    #expect(history.lostRuntimeValues == 2)
}

@Test("Final counters report values still buffered when collection stops")
func finalRuntimeStateReportsUnobservedValues() {
    var history = DiagnosticHistory(capacity: 10)
    history.record(event(sequence: 1))
    history.recordFinalRuntimeState(
        streamDropped: 1,
        presenceUncertain: true,
        diagnosticsEmitted: 4
    )

    #expect(history.lostRuntimeValues == 3)
    #expect(history.uncertainty == [.runtimeStreamLoss, .sequenceGap, .presenceUncertain])
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

@Test("Rolling capture rejects an event larger than its file bound")
func captureRejectsOversizedEvent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("axoloty-capture-oversize-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try DiagnosticCapture(
        configuration: DiagnosticCaptureConfiguration(directory: directory, maximumFileBytes: 1024)
    )
    let oversized = event(
        sequence: 1,
        attributes: ["value": String(repeating: "x", count: 2048)],
        policy: DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: true)
    )

    #expect(throws: DiagnosticCaptureError.cannotWrite("event exceeds maximum capture file size")) {
        try capture.append(oversized)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test("Nothing is written without an explicit capture")
func noImplicitCapture() {
    var history = DiagnosticHistory(capacity: 1)
    history.record(event(sequence: 1))
    #expect(history.events.count == 1)
}
