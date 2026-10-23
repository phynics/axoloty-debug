// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// Independent access protection for an MCP HTTP listener.
///
/// The token is separate from ``MCPAccessPolicy``: it authenticates the
/// caller before any MCP request is processed, so a remote endpoint keeps its
/// read-only policy even if the token leaks. Use a long random value and keep
/// it out of shell history and process arguments; the executable reads it from
/// a file.
public struct MCPAccessProtection: Sendable, Equatable {
    /// The bearer token every HTTP request must present.
    public let bearerToken: String

    /// Creates access protection for a bearer token.
    ///
    /// Surrounding whitespace is discarded. A token that is empty after
    /// trimming, or that contains interior whitespace, is rejected.
    ///
    /// - Parameter bearerToken: The shared bearer token.
    public init?(bearerToken: String) {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isWhitespace) else {
            return nil
        }
        self.bearerToken = token
    }
}
