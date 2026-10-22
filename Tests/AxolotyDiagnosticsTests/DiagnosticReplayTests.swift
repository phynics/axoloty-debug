// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

@testable import AxolotyDiagnostics
import Foundation
import Testing

private func event(_ sequence: UInt64) -> DiagnosticEvent {
    DiagnosticEvent(
        family: .lifecycle,
        label: "reconnected",
        attributes: ["attempt": "\(sequence)"],
        detail: "",
        provenance: DiagnosticProvenance(origin: .runtimeStream, runtimeSequence: sequence, runtimeTimestampMS: UInt32(sequence))
    )
}

private func history(_ sequences: [UInt64], capacity: Int = 100) -> DiagnosticHistory {
    var history = DiagnosticHistory(capacity: capacity)
    sequences.forEach { history.record(event($0)) }
    return history
}

@Test("A complete export replays as deterministic full")
func completeExportIsFull() throws {
    let data = try DiagnosticExport(history: history([1, 2, 3])).encoded()
    let replay = try DiagnosticReplay(exportData: data)
    #expect(replay.verdict == .deterministicFull)
    #expect(replay.events.map(\.provenance.runtimeSequence) == [1, 2, 3])
}

@Test("Replay delivers events in recorded order")
func replayIsOrdered() throws {
    let replay = try DiagnosticReplay(exportData: DiagnosticExport(history: history([1, 2, 3])).encoded())
    var seen: [UInt64] = []
    replay.replay { seen.append($0.provenance.runtimeSequence) }
    #expect(seen == [1, 2, 3])
}

@Test("Overflow, gaps, and late starts refuse a full claim")
func incompleteRecordsAreRefused() throws {
    let overflow = try DiagnosticReplay(exportData: DiagnosticExport(history: history([1, 2, 3, 4], capacity: 2)).encoded())
    #expect(overflow.verdict.isDeterministicFull == false)

    let gap = try DiagnosticReplay(exportData: DiagnosticExport(history: history([1, 4])).encoded())
    guard case let .partial(gapReasons) = gap.verdict else { Issue.record("expected partial"); return }
    #expect(gapReasons.contains(.sequenceGap))

    let late = try DiagnosticReplay(exportData: DiagnosticExport(history: history([5, 6])).encoded())
    guard case let .partial(lateReasons) = late.verdict else { Issue.record("expected partial"); return }
    #expect(lateReasons.contains(.missingLeadingEvents))
}

@Test("Runtime stream loss and uncertain presence refuse a full claim")
func runtimeStateRefusesFull() throws {
    var source = history([1, 2])
    source.recordRuntimeState(streamDropped: 1, presenceUncertain: true)
    let replay = try DiagnosticReplay(exportData: DiagnosticExport(history: source).encoded())
    guard case let .partial(reasons) = replay.verdict else { Issue.record("expected partial"); return }
    #expect(reasons.contains(.runtimeStreamLoss))
    #expect(reasons.contains(.presenceUncertain))
}

@Test("Unknown format versions are rejected")
func unknownVersionRejected() throws {
    let json = Data("{\"formatVersion\": 99}".utf8)
    #expect(throws: DiagnosticReplayError.unsupportedVersion(99)) {
        _ = try DiagnosticReplay(exportData: json)
    }
}

@Test("Malformed input is rejected")
func malformedRejected() {
    #expect(throws: DiagnosticReplayError.self) { _ = try DiagnosticReplay(exportData: Data("nope".utf8)) }
}

@Test("A raw capture can never be claimed as a full replay")
func captureIsAlwaysPartial() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = Data()
    for sequence in 1...3 as ClosedRange<UInt64> {
        data.append(try encoder.encode(event(sequence)))
        data.append(0x0A)
    }
    let replay = try DiagnosticReplay(captureData: data)
    #expect(replay.events.count == 3)
    #expect(replay.verdict == .partial([.noCompletenessRecord]))
}

@Test("The export records the redaction policy and writes only where asked")
func exportRecordsPolicyAndWritesExplicitly() throws {
    let export = DiagnosticExport(
        history: history([1]),
        policy: DiagnosticRedactionPolicy(revealDetail: true, revealIdentities: false)
    )
    #expect(export.revealsDetail && !export.revealsIdentities)
    #expect(export.formatVersion == DiagnosticExport.currentVersion)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("axoloty-export-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try export.write(to: url)
    let replay = try DiagnosticReplay(exportData: Data(contentsOf: url))
    #expect(replay.verdict == .deterministicFull)
}
