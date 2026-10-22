// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

/// The family of runtime evidence an event describes.
public enum DiagnosticFamily: String, Sendable, Equatable, Codable, CaseIterable {
    /// A runtime lifecycle transition.
    case lifecycle
    /// A reconnect attempt.
    case reconnect
    /// Admission or saturation of a bounded resource.
    case admission
    /// The outcome of one request correlation.
    case request
    /// A change in observable object presence.
    case presence
    /// A transport failure.
    case transportFailure
    /// Supported capabilities and capacities.
    case capabilities
    /// A runtime diagnostic that carries no typed observation.
    case other
}

/// Where an event came from and how much it can be trusted.
public struct DiagnosticProvenance: Sendable, Equatable, Codable {
    /// Where the event was read from.
    public enum Origin: String, Sendable, Equatable, Codable {
        /// The runtime's bounded diagnostic stream.
        case runtimeStream
        /// A coalesced runtime diagnostics snapshot.
        case runtimeSnapshot
    }

    /// The source the event was read from.
    public let origin: Origin
    /// The sequence number the runtime assigned, or `0` when it assigned none.
    public let runtimeSequence: UInt64
    /// The monotonic runtime time, in milliseconds, at which the value was emitted.
    public let runtimeTimestampMS: UInt32

    /// Creates provenance for one event.
    ///
    /// - Parameters:
    ///   - origin: The source the event was read from.
    ///   - runtimeSequence: The runtime-assigned sequence number.
    ///   - runtimeTimestampMS: The monotonic runtime emission time.
    public init(origin: Origin, runtimeSequence: UInt64, runtimeTimestampMS: UInt32) {
        self.origin = origin
        self.runtimeSequence = runtimeSequence
        self.runtimeTimestampMS = runtimeTimestampMS
    }
}

/// Controls which potentially sensitive metadata survives ingestion.
///
/// The default policy redacts both the free-form detail string and object,
/// source, and correlation identities. Revealing either is an explicit choice.
public struct DiagnosticRedactionPolicy: Sendable, Equatable {
    /// The marker that replaces redacted values.
    public static let marker = "<redacted>"

    /// The attribute keys that carry identities.
    public static let identityKeys: Set<String> = ["sourceID", "objectID", "correlationID"]

    /// Keeps the free-form detail string when `true`.
    public var revealDetail: Bool
    /// Keeps identity attributes when `true`.
    public var revealIdentities: Bool

    /// Creates a policy. Both flags default to redaction.
    ///
    /// - Parameters:
    ///   - revealDetail: Keep the free-form detail string.
    ///   - revealIdentities: Keep identity attributes.
    public init(revealDetail: Bool = false, revealIdentities: Bool = false) {
        self.revealDetail = revealDetail
        self.revealIdentities = revealIdentities
    }

    /// The default policy, which redacts everything sensitive.
    public static let redactAll = DiagnosticRedactionPolicy()
}

/// One presentation-neutral diagnostic event.
///
/// The event is already redacted according to the policy in force when it was
/// built; a redacted value is never recoverable from the event.
public struct DiagnosticEvent: Sendable, Equatable, Codable {
    /// The evidence family.
    public let family: DiagnosticFamily
    /// A stable machine-readable label, such as the runtime diagnostic kind.
    public let label: String
    /// Typed, payload-free fields rendered as strings.
    public let attributes: [String: String]
    /// Free-form operational context, or the redaction marker.
    public let detail: String
    /// Where the event came from.
    public let provenance: DiagnosticProvenance

    /// Creates an event, applying `policy` to the detail and identities.
    ///
    /// - Parameters:
    ///   - family: The evidence family.
    ///   - label: A stable machine-readable label.
    ///   - attributes: Typed fields rendered as strings.
    ///   - detail: Free-form operational context.
    ///   - provenance: Where the event came from.
    ///   - policy: The redaction policy to apply.
    public init(
        family: DiagnosticFamily,
        label: String,
        attributes: [String: String],
        detail: String,
        provenance: DiagnosticProvenance,
        policy: DiagnosticRedactionPolicy = .redactAll
    ) {
        self.family = family
        self.label = label
        self.attributes = attributes.reduce(into: [:]) { result, pair in
            let sensitive = DiagnosticRedactionPolicy.identityKeys.contains(pair.key)
            result[pair.key] = sensitive && !policy.revealIdentities
                ? DiagnosticRedactionPolicy.marker
                : pair.value
        }
        self.detail = policy.revealDetail || detail.isEmpty ? detail : DiagnosticRedactionPolicy.marker
        self.provenance = provenance
    }
}
