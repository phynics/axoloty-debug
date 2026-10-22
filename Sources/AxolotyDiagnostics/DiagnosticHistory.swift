// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

/// Why a history cannot be treated as a complete record.
public enum DiagnosticUncertainty: String, Sendable, Equatable, Codable, CaseIterable {
    /// The history evicted its oldest events to stay within its capacity.
    case historyOverflow
    /// The runtime's bounded stream dropped values before the consumer read them.
    case runtimeStreamLoss
    /// A sequence gap showed that values were lost between two reads.
    case sequenceGap
    /// A runtime sequence moved backwards between two reads.
    case sequenceRegression
    /// An event had no runtime-assigned sequence number.
    case unsequencedEvents
    /// A transport reset made peer presence non-authoritative.
    case presenceUncertain
}

/// A bounded, in-memory history of diagnostic events with overflow reporting.
///
/// The history keeps the newest events. It never grows beyond `capacity`, and
/// it records every loss it can observe so that a presenter can say how
/// reliable the record is.
public struct DiagnosticHistory: Sendable, Equatable {
    /// The largest number of events retained.
    public let capacity: Int
    /// The retained events, oldest first.
    public private(set) var events: [DiagnosticEvent] = []
    /// The number of events evicted to stay within `capacity`.
    public private(set) var evictedCount: UInt64 = 0
    /// The number of runtime values known to be lost, from sequence gaps and
    /// snapshot drop counters.
    public private(set) var lostRuntimeValues: UInt64 = 0
    /// Whether the runtime reported peer presence as non-authoritative.
    public private(set) var presenceUncertain = false

    private var lastRuntimeSequence: UInt64?
    private var observedRuntimeValues: UInt64 = 0
    private var observedSequenceGap = false
    private var observedSequenceRegression = false
    private var observedStreamLoss = false
    private var observedUnsequencedEvents = false

    /// Creates an empty history.
    ///
    /// - Parameter capacity: The largest number of events retained. Values
    ///   below one are raised to one.
    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// The reasons the history is not a complete record. Empty means complete
    /// as far as the history can tell.
    public var uncertainty: [DiagnosticUncertainty] {
        var reasons: [DiagnosticUncertainty] = []
        if evictedCount > 0 { reasons.append(.historyOverflow) }
        if observedStreamLoss { reasons.append(.runtimeStreamLoss) }
        if observedSequenceGap { reasons.append(.sequenceGap) }
        if observedSequenceRegression { reasons.append(.sequenceRegression) }
        if observedUnsequencedEvents { reasons.append(.unsequencedEvents) }
        if presenceUncertain { reasons.append(.presenceUncertain) }
        return reasons
    }

    /// Appends one event, evicting the oldest when the history is full.
    ///
    /// A jump in the runtime sequence number is recorded as loss.
    ///
    /// - Parameter event: The event to retain.
    public mutating func record(_ event: DiagnosticEvent) {
        let sequence = event.provenance.runtimeSequence
        if event.provenance.origin == .runtimeStream {
            let (observed, overflow) = observedRuntimeValues.addingReportingOverflow(1)
            observedRuntimeValues = overflow ? .max : observed
        }
        if sequence == 0 {
            observedUnsequencedEvents = true
        } else {
            if let last = lastRuntimeSequence, sequence > last {
                if sequence - last > 1 {
                    let gap = sequence - last - 1
                    let (total, overflow) = lostRuntimeValues.addingReportingOverflow(gap)
                    lostRuntimeValues = overflow ? .max : total
                    observedSequenceGap = true
                }
                lastRuntimeSequence = sequence
            } else if let last = lastRuntimeSequence, sequence < last {
                observedSequenceRegression = true
            } else if lastRuntimeSequence == nil {
                lastRuntimeSequence = sequence
            }
        }
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
            evictedCount += UInt64(1)
        }
    }

    /// Folds the runtime's own loss and presence reporting into the history.
    ///
    /// - Parameters:
    ///   - streamDropped: The runtime's cumulative count of dropped stream values.
    ///   - presenceUncertain: Whether peer presence is non-authoritative.
    public mutating func recordRuntimeState(streamDropped: UInt64, presenceUncertain: Bool) {
        if streamDropped > 0 {
            observedStreamLoss = true
            lostRuntimeValues = max(lostRuntimeValues, streamDropped)
        }
        self.presenceUncertain = self.presenceUncertain || presenceUncertain
    }

    /// Folds final runtime counters into the history after its stream consumer ends.
    ///
    /// The difference between emitted and observed values is reported as loss,
    /// including values still buffered when collection stopped.
    ///
    /// - Parameters:
    ///   - streamDropped: The runtime's cumulative count of dropped stream values.
    ///   - presenceUncertain: Whether peer presence is non-authoritative.
    ///   - diagnosticsEmitted: The runtime's cumulative count of emitted values.
    public mutating func recordFinalRuntimeState(
        streamDropped: UInt64,
        presenceUncertain: Bool,
        diagnosticsEmitted: UInt64
    ) {
        recordRuntimeState(streamDropped: streamDropped, presenceUncertain: presenceUncertain)
        guard diagnosticsEmitted > observedRuntimeValues else { return }
        let missingValues = diagnosticsEmitted - observedRuntimeValues
        lostRuntimeValues = max(lostRuntimeValues, missingValues)
        observedSequenceGap = true
    }

    /// Returns a copy with sensitive event fields redacted under `policy`.
    ///
    /// Existing uncertainty and loss counts are preserved. Redaction is
    /// irreversible because the original event values are not retained.
    ///
    /// - Parameter policy: The policy to apply to each retained event.
    /// - Returns: A history with the same completeness state and redacted data.
    public func redacted(using policy: DiagnosticRedactionPolicy = .redactAll) -> DiagnosticHistory {
        var history = self
        history.events = events.map { event in
            DiagnosticEvent(
                family: event.family,
                label: event.label,
                attributes: event.attributes,
                detail: event.detail,
                provenance: event.provenance,
                policy: policy
            )
        }
        return history
    }
}
