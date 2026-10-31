// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Axoloty
import AxolotyDiagnostics
import AxolotyWire

/// Converts Core's owned runtime diagnostics into the shared tooling model.
enum RuntimeDiagnosticAdapter {
    static func events(
        from snapshot: RuntimeDiagnostics,
        policy: DiagnosticRedactionPolicy
    ) -> [DiagnosticEvent] {
        var events = [
            DiagnosticEvent(
                family: .lifecycle,
                label: "lifecycleSnapshot",
                attributes: [
                    "state": String(describing: snapshot.lifecycleState),
                    "from": String(describing: snapshot.lifecycle.from),
                    "to": String(describing: snapshot.lifecycle.to),
                    "transportEpoch": String(snapshot.lifecycle.transportEpoch),
                ],
                detail: "",
                provenance: snapshotProvenance,
                policy: policy
            ),
            DiagnosticEvent(
                family: .capabilities,
                label: "capabilitiesSnapshot",
                attributes: capabilityAttributes(snapshot.capabilities),
                detail: "",
                provenance: snapshotProvenance,
                policy: policy
            ),
        ]

        if let reconnect = snapshot.lastReconnect {
            events.append(DiagnosticEvent(
                family: .reconnect,
                label: "reconnectSnapshot",
                attributes: [
                    "cause": String(describing: reconnect.cause),
                    "attempt": String(reconnect.attempt),
                    "transportEpoch": String(reconnect.transportEpoch),
                ],
                detail: "",
                provenance: snapshotProvenance,
                policy: policy
            ))
        }
        if let presence = snapshot.lastPresence {
            events.append(DiagnosticEvent(
                family: .presence,
                label: "presenceSnapshot",
                attributes: [
                    "sourceID": presence.sourceID.map(InspectorUUID.string) ?? "",
                    "objectID": presence.objectID.map(InspectorUUID.string) ?? "",
                    "evidence": String(describing: presence.evidence),
                    "activeObjects": String(presence.activeObjects),
                    "generation": String(presence.generation),
                ],
                detail: "",
                provenance: snapshotProvenance,
                policy: policy
            ))
        }
        return events
    }

    static func event(
        from diagnostic: RuntimeDiagnostic,
        policy: DiagnosticRedactionPolicy
    ) -> DiagnosticEvent {
        let family: DiagnosticFamily
        var attributes: [String: String] = [:]

        switch diagnostic.observation {
        case let .lifecycle(observation):
            family = .lifecycle
            attributes = [
                "from": String(describing: observation.from),
                "to": String(describing: observation.to),
                "transportEpoch": String(observation.transportEpoch),
            ]
        case let .reconnect(observation):
            family = .reconnect
            attributes = [
                "cause": String(describing: observation.cause),
                "attempt": String(observation.attempt),
                "transportEpoch": String(observation.transportEpoch),
            ]
        case let .admission(observation):
            family = .admission
            attributes = [
                "resource": String(describing: observation.resource),
                "outcome": String(describing: observation.outcome),
                "capacity": String(observation.capacity),
            ]
        case let .request(observation):
            family = .request
            attributes = [
                "capability": observation.capability.map(String.init(describing:)) ?? "unknown",
                "correlationID": observation.correlationID.map(InspectorUUID.string) ?? "",
                "outcome": String(describing: observation.outcome),
                "rejection": observation.rejection.map(String.init(describing:)) ?? "",
            ]
        case let .presence(observation):
            family = .presence
            attributes = [
                "sourceID": observation.sourceID.map(InspectorUUID.string) ?? "",
                "objectID": observation.objectID.map(InspectorUUID.string) ?? "",
                "evidence": String(describing: observation.evidence),
                "activeObjects": String(observation.activeObjects),
                "generation": String(observation.generation),
            ]
        case let .transportFailure(observation):
            family = .transportFailure
            attributes = ["code": String(describing: observation.code)]
        case let .capabilities(capabilities):
            family = .capabilities
            attributes = capabilityAttributes(capabilities)
        case nil:
            switch diagnostic.kind {
            case .capacityExceeded:
                family = .admission
            case .requestAccepted, .requestCancelled, .requestExpired, .requestRejected, .responseReceived:
                family = .request
            case .presenceChanged:
                family = .presence
            case .reconnected:
                family = .reconnect
            case .transportFailed:
                family = .transportFailure
            case .handlerFailed, .malformedFrame, .malformedPayload, .staleTransportFrame:
                family = .other
            }
        }

        return DiagnosticEvent(
            family: family,
            label: diagnostic.kind.rawValue,
            attributes: attributes,
            detail: diagnostic.detail,
            provenance: DiagnosticProvenance(
                origin: .runtimeStream,
                runtimeSequence: diagnostic.sequence,
                runtimeTimestampMS: diagnostic.timestampMS
            ),
            policy: policy
        )
    }

    private static var snapshotProvenance: DiagnosticProvenance {
        DiagnosticProvenance(origin: .runtimeSnapshot, runtimeSequence: 0, runtimeTimestampMS: 0)
    }

    private static func capabilityAttributes(_ capabilities: RuntimeCapabilityInformation) -> [String: String] {
        [
            "protocolCapabilities": String(describing: capabilities.protocolCapabilities),
            "wireProfile": String(describing: capabilities.wireProfile),
            "maximumPayloadBytes": String(capabilities.maximumPayloadBytes),
            "maximumObjects": String(capabilities.maximumObjects),
            "maximumPendingCorrelations": String(capabilities.maximumPendingCorrelations),
            "diagnosticCapacity": String(capabilities.diagnosticCapacity),
        ]
    }
}
