// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyDiagnostics
import AxolotyInspectorCore
import Foundation

/// Collects the shared runtime diagnostic history and writes a versioned JSON export.
@MainActor
public final class InspectorDiagnosticsApplication {
    private let configuration: InspectorConfiguration
    private let session: InspectorSession
    private let writeOutput: (String) -> Void
    private let writeDiagnostic: (String) -> Void
    private let signalHandler: InspectorSignalHandling?

    /// Creates the diagnostics application.
    ///
    /// - Parameters:
    ///   - configuration: The parsed diagnostics command and connection options.
    ///   - session: The runtime session that supplies diagnostic events.
    ///   - writeOutput: Writes the versioned JSON export to standard output.
    ///   - writeDiagnostic: Writes human-readable diagnostics to standard error.
    ///   - signalHandler: The caller-owned signal observer, if installed.
    public init(
        configuration: InspectorConfiguration,
        session: InspectorSession,
        writeOutput: @escaping (String) -> Void,
        writeDiagnostic: @escaping (String) -> Void,
        signalHandler: InspectorSignalHandling? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.writeOutput = writeOutput
        self.writeDiagnostic = writeDiagnostic
        self.signalHandler = signalHandler
    }

    /// Collects diagnostics for the configured duration and exports the history.
    ///
    /// - Returns: An ``InspectorError`` when connection, capture, or export fails.
    public func run() async -> InspectorError? {
        guard case let .diagnostics(command) = configuration.command else {
            return .invalidArguments(reason: "non-diagnostics command passed to diagnostics application")
        }

        let policy = DiagnosticRedactionPolicy(
            revealDetail: command.revealDetail,
            revealIdentities: command.revealIdentities
        )
        let captureConfiguration = command.captureDirectory.map {
            DiagnosticCaptureConfiguration(directory: URL(fileURLWithPath: $0, isDirectory: true))
        }
        do {
            try session.configureDiagnostics(
                redactionPolicy: policy,
                captureConfiguration: captureConfiguration
            )
        } catch {
            let message = String(describing: error)
            writeDiagnostic("error: \(message)")
            return .outputFailure(reason: message)
        }

        do {
            try await session.connect()
        } catch let error as InspectorError {
            writeDiagnostic("error: \(error.userFriendlyMessage)")
            await session.stop()
            return error
        } catch {
            let message = String(describing: error)
            writeDiagnostic("error: \(message)")
            await session.stop()
            return .connectionUnavailable(reason: message)
        }

        let interrupted = await collect(for: command.duration)
        await session.stop()
        let history = await session.diagnosticHistory()
        let captureFailure = session.diagnosticCaptureFailure()
        do {
            let data = try DiagnosticExport(history: history, policy: policy).encoded()
            writeOutput(String(decoding: data, as: UTF8.self))
        } catch {
            let message = String(describing: error)
            writeDiagnostic("error: \(message)")
            return .outputFailure(reason: message)
        }

        if let captureFailure {
            let message = String(describing: captureFailure)
            writeDiagnostic("error: rolling diagnostic capture failed: \(message)")
            return .outputFailure(reason: message)
        }
        return interrupted ? .interrupted : nil
    }

    private func collect(for duration: InspectorDuration) async -> Bool {
        if let duration = duration.value {
            guard let signalHandler else {
                try? await Task.sleep(for: duration)
                return false
            }
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: duration)
            while !signalHandler.wasInterrupted && !Task.isCancelled && clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            return signalHandler.wasInterrupted
        }

        guard let signalHandler else {
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)) }
            return false
        }
        while !signalHandler.wasInterrupted && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return signalHandler.wasInterrupted
    }
}
