// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// Why a replay cannot claim to reproduce the original run in full.
public enum DiagnosticReplayLimitation: String, Sendable, Equatable, Codable, CaseIterable {
    /// The history evicted events before it was exported.
    case historyOverflow
    /// The runtime's bounded stream dropped values before they were read.
    case runtimeStreamLoss
    /// A sequence gap shows that values are missing from the middle.
    case sequenceGap
    /// Runtime sequence numbers moved backwards in the record.
    case sequenceRegression
    /// Peer presence was non-authoritative when the record was taken.
    case presenceUncertain
    /// The first retained event is not the runtime's first value, so earlier
    /// traffic was not captured.
    case missingLeadingEvents
    /// Some events carry no runtime sequence, so their order is not proven.
    case unsequencedEvents
    /// The source has no completeness record, such as a raw capture file.
    case noCompletenessRecord
}

/// What a replay may honestly claim.
public enum DiagnosticReplayVerdict: Sendable, Equatable {
    /// The record is complete and ordered by runtime sequence.
    case deterministicFull
    /// The record is usable but cannot be called a full replay.
    case partial([DiagnosticReplayLimitation])

    /// Whether a deterministic full replay may be claimed.
    public var isDeterministicFull: Bool { self == .deterministicFull }
}

/// A deterministic, in-memory replay of exported diagnostic events.
///
/// Replay delivers events in recorded order and never invents state. It
/// refuses to claim a deterministic full replay unless the record proves it is
/// complete.
public struct DiagnosticReplay: Sendable, Equatable {
    /// The events, oldest first.
    public let events: [DiagnosticEvent]
    /// What the replay may honestly claim.
    public let verdict: DiagnosticReplayVerdict

    /// Reads an export produced by ``DiagnosticExport``.
    ///
    /// - Parameter data: The encoded export.
    /// - Returns: A replay of the exported events.
    /// - Throws: ``DiagnosticReplayError/unsupportedVersion(_:)`` for an
    ///   unknown format version, or ``DiagnosticReplayError/malformed(_:)``.
    public init(exportData data: Data) throws(DiagnosticReplayError) {
        struct Header: Decodable { let formatVersion: Int }
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw .malformed("\(error)")
        }
        guard header.formatVersion == DiagnosticExport.currentVersion else {
            throw .unsupportedVersion(header.formatVersion)
        }
        let export: DiagnosticExport
        do {
            export = try decoder.decode(DiagnosticExport.self, from: data)
        } catch {
            throw .malformed("\(error)")
        }
        var limitations = Self.limitations(for: export.uncertainty)
        limitations.append(contentsOf: Self.sequenceLimitations(export.events))
        self.events = export.events
        self.verdict = Self.verdict(limitations)
    }

    /// Reads a rolling JSON-lines capture written by ``DiagnosticCapture``.
    ///
    /// A capture carries no completeness record, so the verdict is always
    /// partial.
    ///
    /// - Parameter captureData: The concatenated capture files.
    /// - Returns: A replay of the captured events.
    /// - Throws: ``DiagnosticReplayError/malformed(_:)`` for an invalid line.
    public init(captureData: Data) throws(DiagnosticReplayError) {
        let decoder = JSONDecoder()
        var events: [DiagnosticEvent] = []
        for line in captureData.split(separator: 0x0A, omittingEmptySubsequences: true) {
            do {
                events.append(try decoder.decode(DiagnosticEvent.self, from: Data(line)))
            } catch {
                throw .malformed("\(error)")
            }
        }
        var limitations: [DiagnosticReplayLimitation] = [.noCompletenessRecord]
        limitations.append(contentsOf: Self.sequenceLimitations(events))
        self.events = events
        self.verdict = Self.verdict(limitations)
    }

    /// Delivers every event to `sink` in recorded order.
    ///
    /// - Parameter sink: Receives each event.
    public func replay(into sink: (DiagnosticEvent) -> Void) {
        events.forEach(sink)
    }

    private static func limitations(for uncertainty: [DiagnosticUncertainty]) -> [DiagnosticReplayLimitation] {
        uncertainty.map { reason in
            switch reason {
            case .historyOverflow: .historyOverflow
            case .runtimeStreamLoss: .runtimeStreamLoss
            case .sequenceGap: .sequenceGap
            case .sequenceRegression: .sequenceRegression
            case .unsequencedEvents: .unsequencedEvents
            case .presenceUncertain: .presenceUncertain
            }
        }
    }

    private static func sequenceLimitations(_ events: [DiagnosticEvent]) -> [DiagnosticReplayLimitation] {
        var result: [DiagnosticReplayLimitation] = []
        let sequences = events.map(\.provenance.runtimeSequence)
        if sequences.contains(0) { result.append(.unsequencedEvents) }
        let proven = sequences.filter { $0 != 0 }
        if let first = proven.first, first != 1 { result.append(.missingLeadingEvents) }
        for (previous, next) in zip(proven, proven.dropFirst()) {
            if next <= previous {
                result.append(.sequenceRegression)
            } else if next - previous > 1 {
                result.append(.sequenceGap)
            }
        }
        return result
    }

    private static func verdict(_ limitations: [DiagnosticReplayLimitation]) -> DiagnosticReplayVerdict {
        var unique: [DiagnosticReplayLimitation] = []
        for limitation in limitations where !unique.contains(limitation) { unique.append(limitation) }
        return unique.isEmpty ? .deterministicFull : .partial(unique)
    }
}
