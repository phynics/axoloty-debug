// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Crypto
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
    private let comparisonKeyBytes: [UInt8]

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
        self.comparisonKeyBytes = Self.fixedComparisonKeyBytes(bytes)
    }

    func matches(_ candidate: String) -> Bool {
        let bytes = Array(candidate.utf8)
        guard bytes.count <= Self.maximumTokenBytes else { return false }
        let candidateKeyBytes = Self.fixedComparisonKeyBytes(bytes)
        let challenge = Data(repeating: 0, count: MemoryLayout<UInt64>.size)
        let candidateCode = HMAC<SHA256>.authenticationCode(
            for: challenge,
            using: SymmetricKey(data: Data(candidateKeyBytes))
        )
        // Swift Crypto verifies fixed-size HMAC codes with its constant-time comparison.
        return HMAC<SHA256>.isValidAuthenticationCode(
            candidateCode,
            authenticating: challenge,
            using: SymmetricKey(data: Data(comparisonKeyBytes))
        )
    }

    private static func fixedComparisonKeyBytes(_ tokenBytes: [UInt8]) -> [UInt8] {
        var keyBytes = [UInt8](repeating: 0, count: MemoryLayout<UInt64>.size + maximumTokenBytes)
        var tokenLength = UInt64(tokenBytes.count).bigEndian
        withUnsafeBytes(of: &tokenLength) { lengthBytes in
            keyBytes.replaceSubrange(0..<lengthBytes.count, with: lengthBytes)
        }
        let tokenStart = MemoryLayout<UInt64>.size
        keyBytes.replaceSubrange(tokenStart..<(tokenStart + tokenBytes.count), with: tokenBytes)
        return keyBytes
    }
}
