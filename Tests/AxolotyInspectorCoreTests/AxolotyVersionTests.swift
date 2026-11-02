// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyVersion
import Foundation
import Testing

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func versionFileContents() throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent("VERSION"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct ScriptResult {
    var status: Int32
    var standardError: String
}

private func runStampScript(_ mode: String, root: URL) throws -> ScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [repositoryRoot.appendingPathComponent("scripts/stamp-version.sh").path, mode, root.path]
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ScriptResult(status: process.terminationStatus, standardError: String(decoding: data, as: UTF8.self))
}

/// Copies VERSION and the version source into a scratch tree.
private func scratchTree(version: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("axoloty-version-\(UUID().uuidString)")
    let source = root.appendingPathComponent("Sources/AxolotyVersion")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
        at: repositoryRoot.appendingPathComponent("Sources/AxolotyVersion/AxolotyVersion.swift"),
        to: source.appendingPathComponent("AxolotyVersion.swift")
    )
    try (version + "\n").write(to: root.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
    return root
}

@Test("The committed version is the development form of VERSION")
func committedVersionIsDevelopmentFormOfVersionFile() throws {
    #expect(AxolotyVersion.compiledVersion == "\(try versionFileContents())-dev")
    #expect(!AxolotyVersion.isReleaseBuild)
}

@Test("A development build never reports a bare release number")
func developmentBuildIsDistinguishable() {
    let version = AxolotyVersion.current(environment: [:])
    #expect(version == AxolotyVersion.compiledVersion)
    #expect(version.hasSuffix(AxolotyVersion.developmentSuffix))
}

@Test("An explicit AXOLOTY_VERSION still wins")
func explicitVersionOverridesCompiledInValue() {
    #expect(AxolotyVersion.current(environment: ["AXOLOTY_VERSION": "9.9.9"]) == "9.9.9")
}

@Test("The stamp script accepts the committed tree and stamps the release number from VERSION")
func stampScriptDerivesReleaseVersionFromVersionFile() throws {
    let root = try scratchTree(version: try versionFileContents())
    defer { try? FileManager.default.removeItem(at: root) }
    let release = try versionFileContents()

    #expect(try runStampScript("check", root: root).status == 0)
    #expect(try runStampScript("release", root: root).status == 0)

    let stamped = try String(
        contentsOf: root.appendingPathComponent("Sources/AxolotyVersion/AxolotyVersion.swift"),
        encoding: .utf8
    )
    #expect(stamped.contains("compiledVersion = \"\(release)\"\n"))
    #expect(!stamped.contains("compiledVersion = \"\(release)-dev\""))
    // A stamped tree is not a valid input: stamping twice cannot hide a mismatch.
    #expect(try runStampScript("release", root: root).status == 1)
}

@Test("A VERSION bump without the matching literal stops the release")
func stampScriptRejectsVersionMismatch() throws {
    let root = try scratchTree(version: "99.0.0")
    defer { try? FileManager.default.removeItem(at: root) }

    let check = try runStampScript("check", root: root)
    #expect(check.status == 1)
    #expect(check.standardError.contains("expected '99.0.0-dev'"))
    #expect(try runStampScript("release", root: root).status == 1)
}
