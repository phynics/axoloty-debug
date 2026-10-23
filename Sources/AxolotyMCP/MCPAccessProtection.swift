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
    /// Maximum UTF-8 token length accepted by this implementation.
    public static let maximumTokenBytes = 4_096

    /// The bearer token every HTTP request must present.
    public let bearerToken: String
    private let comparisonBytes: [UInt8]
    private let tokenLength: Int

    /// Creates access protection for a bearer token.
    ///
    /// Surrounding whitespace is discarded. A token that is empty after
    /// trimming, contains interior whitespace, or exceeds
    /// ``maximumTokenBytes`` UTF-8 bytes is rejected.
    ///
    /// - Parameter bearerToken: The shared bearer token.
    public init?(bearerToken: String) {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
            token.utf8.count <= Self.maximumTokenBytes,
            !token.contains(where: \.isWhitespace)
        else {
            return nil
        }
        self.bearerToken = token
        let bytes = Array(token.utf8)
        var fixedBytes = [UInt8](repeating: 0, count: Self.maximumTokenBytes)
        fixedBytes.replaceSubrange(0..<bytes.count, with: bytes)
        self.comparisonBytes = fixedBytes
        self.tokenLength = bytes.count
    }

    func matches(_ candidate: String) -> Bool {
        let bytes = Array(candidate.utf8)
        guard bytes.count <= Self.maximumTokenBytes else { return false }
        var fixedBytes = [UInt8](repeating: 0, count: Self.maximumTokenBytes)
        fixedBytes.replaceSubrange(0..<bytes.count, with: bytes)
        var difference = UInt64(bytes.count ^ tokenLength)
        for index in 0..<Self.maximumTokenBytes {
            difference |= UInt64(fixedBytes[index] ^ comparisonBytes[index])
        }
        return difference == 0
    }
}
