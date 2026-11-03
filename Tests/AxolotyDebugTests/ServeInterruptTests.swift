// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

@testable import AxolotyDebug
import AxolotyDebugTestSupport
import Foundation
import Synchronization
import Testing

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// An interrupt during a readiness wait must end the wait at once.
///
/// Both tests use a child that never becomes ready, so without cancellation the
/// wait runs to its full deadline (15 seconds for `serve mcp`). The time bounds
/// sit well above any scheduling delay and well below that deadline.
@Suite(.serialized)
struct ServeInterruptTests {
    /// Generous upper bound on an interrupted run; the unfixed wait takes about 15 seconds.
    private static let interruptedRunBound: TimeInterval = 8

    private static func freeLoopbackPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        try #require(named == 0)
        return UInt16(bigEndian: address.sin_port)
    }

    private static func processExists(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    @Test(
        "axoloty-debug serve mcp stops promptly and reaps its child when interrupted during the readiness wait",
        arguments: [SIGINT, SIGTERM]
    )
    func interruptDuringMCPReadinessWait(signalNumber: Int32) throws {
        let binary = try #require(MCPExecutableLocation.locateProduct(named: "axoloty-debug"))
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("axoloty-serve-interrupt-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // A stand-in axoloty-mcp that records its pid and never listens.
        let pidFile = root.appendingPathComponent("child.pid")
        let stub = root.appendingPathComponent("axoloty-mcp")
        try "#!/bin/sh\necho $$ > '\(pidFile.path)'\nexec sleep 300\n".write(to: stub, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)

        var environment = ProcessInfo.processInfo.environment
        environment["AXOLOTY_MCP_EXECUTABLE"] = stub.path
        environment["AXOLOTY_MOSQUITTO_EXECUTABLE"] = nil

        let process = Process()
        process.executableURL = binary
        process.arguments = ["serve", "mcp", "--transport", "http", "--listen-port", String(try Self.freeLoopbackPort())]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }

        // The child writing its pid proves axoloty-debug is past start-up and inside the wait.
        var childPID: pid_t?
        let startDeadline = Date().addingTimeInterval(20)
        while childPID == nil, Date() < startDeadline, process.isRunning {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                childPID = pid
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        let child = try #require(childPID, "the stand-in axoloty-mcp never started")
        // Let the supervisor reach the readiness poll before interrupting it.
        Thread.sleep(forTimeInterval: 0.5)

        let interrupted = Date()
        kill(process.processIdentifier, signalNumber)
        let exitDeadline = interrupted.addingTimeInterval(30)
        while process.isRunning, Date() < exitDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let elapsed = Date().timeIntervalSince(interrupted)

        #expect(!process.isRunning, "still running \(elapsed) seconds after signal \(signalNumber)")
        #expect(elapsed < Self.interruptedRunBound, "took \(elapsed) seconds to exit after signal \(signalNumber)")
        if !process.isRunning {
            #expect(process.terminationReason == .exit)
            #expect(process.terminationStatus == 130)
        }
        #expect(!Self.processExists(child), "child \(child) outlived axoloty-debug")
        if Self.processExists(child) { kill(child, SIGKILL) }
    }
}

// MARK: - Runner level

private struct StubFileSystem: AxolotyDebugFileSystem {
    let paths: Set<String>
    func exists(atPath path: String) -> Bool { paths.contains(path) }
}

private final class StubRunner: AxolotyManagedProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var terminated = false

    var wasTerminated: Bool { lock.withLock { terminated } }

    func start(_ specification: ManagedProcessSpecification) throws { lock.withLock { running = true } }
    func waitForExit(timeoutSeconds: TimeInterval) -> ManagedProcessExit? {
        lock.withLock { running ? nil : ManagedProcessExit(exitCode: 0, wasTerminated: terminated) }
    }
    func terminate() { lock.withLock { terminated = true; running = false } }
    func forceKill() { lock.withLock { running = false } }
    var processIdentifier: Int32? { 12345 }
    var processDescription: String { "stub" }
    var isRunning: Bool { lock.withLock { running } }
}

/// A probe whose wait is never satisfied, standing in for a child that is not ready yet.
///
/// Like ``FoundationServiceProbe`` it only ends early through `shouldAbort`;
/// otherwise it blocks for `stallSeconds`, the stand-in for the readiness deadline.
private struct StallingProbe: AxolotyServiceProbing {
    /// Ports that accept at once.
    var readyPorts: Set<UInt16> = []
    var stallSeconds: TimeInterval = 6

    func isPortAvailable(host: String, port: UInt16) -> Bool { true }

    func waitForTCP(host: String, port: UInt16, timeoutSeconds: Double) -> Bool {
        if readyPorts.contains(port) { return true }
        Thread.sleep(forTimeInterval: stallSeconds)
        return false
    }

    func waitForTCP(host: String, port: UInt16, timeoutSeconds: Double, shouldAbort: @Sendable () -> Bool) -> Bool {
        if readyPorts.contains(port) { return true }
        let deadline = Date().addingTimeInterval(stallSeconds)
        while Date() < deadline, !shouldAbort() { usleep(20_000) }
        return false
    }
}

private func runCancelling(
    after delay: TimeInterval,
    cancellation: AxolotyDebugCancellation,
    _ run: () -> Int32
) -> (exitCode: Int32, elapsed: TimeInterval) {
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { cancellation.cancel() }
    let started = Date()
    let exitCode = run()
    return (exitCode, Date().timeIntervalSince(started))
}

@Test("serve mcp cancels its readiness wait and stops the child")
func mcpRunnerCancelsReadinessWait() {
    let cancellation = AxolotyDebugCancellation()
    let child = StubRunner()
    let runner = AxolotyMCPServiceRunner(
        processRunner: child,
        portProbe: StallingProbe(),
        fileSystem: StubFileSystem(paths: ["/opt/axoloty/bin/axoloty-mcp"]),
        installSignalHandler: false,
        cancellation: cancellation
    )

    let outcome = runCancelling(after: 0.3, cancellation: cancellation) {
        runner.run(MCPServiceConfiguration(transport: .http))
    }

    #expect(outcome.exitCode == 130)
    #expect(outcome.elapsed < 3, "took \(outcome.elapsed) seconds to exit")
    #expect(child.wasTerminated)
    #expect(!child.isRunning)
}

@Test("serve dev cancels its MCP readiness wait and stops both children")
func developmentRunnerCancelsMCPReadinessWait() {
    let cancellation = AxolotyDebugCancellation()
    let broker = StubRunner()
    let mcp = StubRunner()
    let children = [broker, mcp]
    let next = Mutex(0)
    let runner = AxolotyDevelopmentServiceRunner(
        processRunnerFactory: { next.withLock { index in defer { index += 1 }; return children[index] } },
        portProbe: StallingProbe(readyPorts: [1883]),
        fileSystem: StubFileSystem(paths: ["/usr/sbin/mosquitto", "/opt/axoloty/bin/axoloty-mcp"]),
        installSignalHandler: false,
        cancellation: cancellation
    )

    let outcome = runCancelling(after: 0.3, cancellation: cancellation) {
        runner.run(DevelopmentServiceConfiguration(
            mqtt: MQTTServiceConfiguration(),
            mcp: MCPServiceConfiguration(transport: .http),
            namespace: "test",
            output: .human
        ))
    }

    #expect(outcome.exitCode == 130)
    #expect(outcome.elapsed < 3, "took \(outcome.elapsed) seconds to exit")
    #expect(broker.wasTerminated)
    #expect(mcp.wasTerminated)
}
