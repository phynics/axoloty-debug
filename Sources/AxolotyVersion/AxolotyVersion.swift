// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// Resolves the version that first-party tooling reports.
public enum AxolotyVersion {
    /// The version compiled into this build.
    ///
    /// The committed value is always `<VERSION>-dev`, so a development build
    /// can never report a release number. The release workflow runs
    /// `scripts/stamp-version.sh release`, which derives the release value from
    /// the root `VERSION` file and rewrites this line before the release build.
    /// The same script refuses to stamp, and fails the release, when the
    /// committed value is not `<VERSION>-dev`. When `VERSION` changes, update
    /// this literal to match; `scripts/stamp-version.sh check` and
    /// `AxolotyVersionTests` fail until it does.
    public static let compiledVersion = "0.1.0-dev"

    /// Suffix that marks an unstamped, development build.
    public static let developmentSuffix = "-dev"

    /// Whether this build was stamped by the release workflow.
    public static var isReleaseBuild: Bool {
        !compiledVersion.hasSuffix(developmentSuffix)
    }

    /// Returns the line a `--version` flag prints: the executable name and the
    /// version, separated by a space, with no trailing newline.
    ///
    /// Every first-party executable prints this one format so an operator can
    /// compare them directly.
    ///
    /// - Parameters:
    ///   - executableName: The executable's name, such as `axoloty-debug`.
    ///   - environment: Process environment passed to ``current(environment:)``.
    /// - Returns: The line to print, such as `axoloty-debug 0.1.0-dev`.
    public static func versionLine(
        executableName: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        "\(executableName) \(current(environment: environment))"
    }

    /// Returns an explicit process value or the compiled-in ``compiledVersion``.
    ///
    /// - Parameter environment: Process environment; a non-empty
    ///   `AXOLOTY_VERSION` overrides the compiled value.
    /// - Returns: The version string to report.
    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let value = environment["AXOLOTY_VERSION"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return compiledVersion
    }
}
