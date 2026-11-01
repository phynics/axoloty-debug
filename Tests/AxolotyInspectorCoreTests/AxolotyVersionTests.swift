// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyVersion
import Foundation
import Testing

@Test("The compiled-in version matches the repository VERSION file")
func releasedVersionMatchesVersionFile() throws {
    let versionFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("VERSION")
    let contents = try String(contentsOf: versionFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(AxolotyVersion.releasedVersion == contents)
}

@Test("A binary without a checkout reports the compiled-in version")
func versionFallsBackToCompiledInValue() {
    let version = AxolotyVersion.current(
        environment: [:],
        sourcePath: "/nonexistent/axoloty-debug-release/Sources/AxolotyVersion/AxolotyVersion.swift"
    )
    #expect(version == AxolotyVersion.releasedVersion)
    #expect(version != "unavailable")
}

@Test("An explicit AXOLOTY_VERSION still wins")
func explicitVersionOverridesCompiledInValue() {
    #expect(AxolotyVersion.current(environment: ["AXOLOTY_VERSION": "9.9.9"]) == "9.9.9")
}
