// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyInspectorCore
import AxolotyInspectorRuntime

/// Decides which MCP tools a client may use and what object data it may see.
///
/// The default policy is read-only and redacting. Active controls require
/// explicit local enablement, and a remote scope can never use controls or
/// receive raw payloads, whatever else is enabled.
public struct MCPAccessPolicy: Sendable, Equatable {
    /// Where the MCP client connects from.
    public enum Scope: Sendable, Equatable {
        /// stdio or a loopback HTTP listener operated by the local user.
        case local
        /// Any endpoint reachable by someone other than the local operator.
        ///
        /// Remote endpoints must also be protected independently of this
        /// policy, for example by a reverse proxy that authenticates callers.
        case remote
    }

    /// Tools that publish traffic or otherwise act on the system.
    public static let controlTools: Set<String> = ["axoloty_discover_objects"]

    /// Tools that only read local state or decode caller-supplied bytes.
    public static let readTools: Set<String> = [
        "axoloty_list_objects",
        "axoloty_get_object",
        "axoloty_decode_payload",
        "axoloty_server_status",
    ]

    /// The scope the policy applies to.
    public let scope: Scope
    /// Whether a local operator enabled control tools.
    public let controlsEnabled: Bool
    /// Whether a local operator allowed raw object payloads and private data.
    public let includePayloads: Bool

    /// Creates a policy.
    ///
    /// - Parameters:
    ///   - scope: Where the client connects from.
    ///   - controlsEnabled: Enable control tools. Ignored for remote scope.
    ///   - includePayloads: Include raw payloads and private data. Ignored for
    ///     remote scope.
    public init(scope: Scope = .local, controlsEnabled: Bool = false, includePayloads: Bool = false) {
        self.scope = scope
        self.controlsEnabled = scope == .local && controlsEnabled
        self.includePayloads = scope == .local && includePayloads
    }

    /// The default policy: local, read-only, redacting.
    public static let localReadOnly = MCPAccessPolicy()

    /// Whether a tool may be listed and called.
    ///
    /// Unknown tools are not allowed.
    ///
    /// - Parameter tool: The tool name.
    /// - Returns: `true` when the policy permits the tool.
    public func allows(tool: String) -> Bool {
        if Self.readTools.contains(tool) { return true }
        if Self.controlTools.contains(tool) { return controlsEnabled }
        return false
    }

    /// Removes raw payloads and private data unless the policy allows them.
    ///
    /// - Parameter object: The catalogue object.
    /// - Returns: The object as the client may see it.
    public func redact(_ object: InspectorObject) -> InspectorObject {
        guard !includePayloads else { return object }
        return InspectorObject(
            objectId: object.objectId,
            coreType: object.coreType,
            objectType: object.objectType,
            name: object.name,
            sourceId: object.sourceId
        )
    }

    /// Redacts every object in a catalogue snapshot.
    ///
    /// - Parameter snapshot: The catalogue snapshot.
    /// - Returns: The snapshot as the client may see it.
    public func redact(_ snapshot: InspectorCatalogueSnapshot) -> InspectorCatalogueSnapshot {
        InspectorCatalogueSnapshot(
            complete: snapshot.complete,
            observedSince: snapshot.observedSince,
            namespace: snapshot.namespace,
            objects: snapshot.objects.map(redact)
        )
    }
}
