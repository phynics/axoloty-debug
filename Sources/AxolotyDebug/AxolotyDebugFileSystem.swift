// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// The filesystem boundary used by the managed service runners.
///
/// The debug package keeps its own copy so it does not depend on the Core
/// build harness. Service runners only ask whether an executable path exists.
public protocol AxolotyDebugFileSystem: Sendable {
    /// Returns whether a path exists.
    func exists(atPath path: String) -> Bool
}

/// Foundation-backed implementation of ``AxolotyDebugFileSystem``.
public struct FoundationDebugFileSystem: AxolotyDebugFileSystem {
    /// Creates a Foundation-backed file-system boundary.
    public init() {}

    public func exists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
