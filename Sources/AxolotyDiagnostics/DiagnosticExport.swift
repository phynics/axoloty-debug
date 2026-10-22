// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// A failure to write, read, or interpret a diagnostic export.
public enum DiagnosticReplayError: Error, Equatable {
    /// The export declares a format version this build cannot interpret.
    case unsupportedVersion(Int)
    /// The bytes are not a valid export or capture.
    case malformed(String)
    /// The export could not be written.
    case cannotWrite(String)
}

/// A versioned, self-describing export of a diagnostic history.
///
/// The export records what the history knew about its own completeness so a
/// later replay can say honestly how much it can claim. Exports are written
/// only when a caller names a destination; nothing is stored implicitly.
public struct DiagnosticExport: Codable, Sendable, Equatable {
    /// The format version this build writes and reads.
    public static let currentVersion = 1

    /// The format version of this export.
    public let formatVersion: Int
    /// Whether free-form detail strings were left unredacted.
    public let revealsDetail: Bool
    /// Whether identities were left unredacted.
    public let revealsIdentities: Bool
    /// The capacity of the history the export came from.
    public let capacity: Int
    /// Events the history evicted to stay within its capacity.
    public let evictedCount: UInt64
    /// Runtime values known to be lost.
    public let lostRuntimeValues: UInt64
    /// The reasons the history was not a complete record.
    public let uncertainty: [DiagnosticUncertainty]
    /// The retained events, oldest first.
    public let events: [DiagnosticEvent]

    /// Creates an export from a history.
    ///
    /// - Parameters:
    ///   - history: The history to export.
    ///   - policy: The redaction policy that was applied to its events.
    public init(history: DiagnosticHistory, policy: DiagnosticRedactionPolicy = .redactAll) {
        self.formatVersion = Self.currentVersion
        self.revealsDetail = policy.revealDetail
        self.revealsIdentities = policy.revealIdentities
        self.capacity = history.capacity
        self.evictedCount = history.evictedCount
        self.lostRuntimeValues = history.lostRuntimeValues
        self.uncertainty = history.uncertainty
        self.events = history.events
    }

    /// Encodes the export as stable JSON.
    ///
    /// - Returns: The encoded bytes.
    /// - Throws: ``DiagnosticReplayError/cannotWrite(_:)`` when encoding fails.
    public func encoded() throws(DiagnosticReplayError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            return try encoder.encode(self)
        } catch {
            throw .cannotWrite("\(error)")
        }
    }

    /// Writes the export to an explicitly chosen file.
    ///
    /// - Parameter url: The destination file.
    /// - Throws: ``DiagnosticReplayError/cannotWrite(_:)`` on failure.
    public func write(to url: URL) throws(DiagnosticReplayError) {
        let data = try encoded()
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .cannotWrite("\(error)")
        }
    }
}
