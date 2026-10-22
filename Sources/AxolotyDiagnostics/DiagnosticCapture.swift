// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import Foundation

/// A failure to write a diagnostic capture.
public enum DiagnosticCaptureError: Error, Equatable {
    /// Capture configuration was changed after runtime observation started.
    case configurationAfterStart
    /// The capture directory or file could not be prepared.
    case cannotPrepare(String)
    /// An event could not be encoded or written.
    case cannotWrite(String)
}

/// Explicit opt-in configuration for rolling on-disk capture.
///
/// Nothing is written unless a caller builds a ``DiagnosticCapture`` from a
/// configuration like this one. Captured events are already redacted by the
/// policy that built them.
public struct DiagnosticCaptureConfiguration: Sendable, Equatable {
    /// The directory that receives the capture files.
    public let directory: URL
    /// The size at which the current file is closed, in bytes.
    public let maximumFileBytes: Int
    /// The number of files kept before the oldest is deleted.
    public let maximumFiles: Int

    /// Creates a capture configuration.
    ///
    /// - Parameters:
    ///   - directory: The directory that receives the capture files.
    ///   - maximumFileBytes: The rotation size. Values below 1 KiB are raised.
    ///   - maximumFiles: The files kept. Values below one are raised to one.
    public init(directory: URL, maximumFileBytes: Int = 1_048_576, maximumFiles: Int = 4) {
        self.directory = directory
        self.maximumFileBytes = max(1024, maximumFileBytes)
        self.maximumFiles = max(1, maximumFiles)
    }
}

/// A rolling JSON-lines capture of diagnostic events.
///
/// The capture is bounded by file size and file count, so it can never fill
/// the disk without limit.
public final class DiagnosticCapture {
    private let configuration: DiagnosticCaptureConfiguration
    private let encoder = JSONEncoder()
    private var index = 0
    private var currentBytes = 0
    private var handle: FileHandle?

    /// Opens a capture, creating its directory.
    ///
    /// - Parameter configuration: The explicit capture configuration.
    /// - Throws: ``DiagnosticCaptureError/cannotPrepare(_:)`` when the
    ///   directory cannot be created.
    public init(configuration: DiagnosticCaptureConfiguration) throws(DiagnosticCaptureError) {
        self.configuration = configuration
        encoder.outputFormatting = [.sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: configuration.directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw .cannotPrepare("\(error)")
        }
    }

    deinit {
        try? handle?.close()
    }

    /// Appends one event as a JSON line, rotating files when needed.
    ///
    /// - Parameter event: The event to capture.
    /// - Throws: ``DiagnosticCaptureError`` when the event cannot be written.
    public func append(_ event: DiagnosticEvent) throws(DiagnosticCaptureError) {
        do {
            var line = try encoder.encode(event)
            line.append(0x0A)
            guard line.count <= configuration.maximumFileBytes else {
                throw DiagnosticCaptureError.cannotWrite("event exceeds maximum capture file size")
            }
            if handle == nil || line.count > configuration.maximumFileBytes - currentBytes {
                try rotate()
            }
            try handle?.write(contentsOf: line)
            currentBytes += line.count
        } catch let error as DiagnosticCaptureError {
            throw error
        } catch {
            throw .cannotWrite("\(error)")
        }
    }

    private func rotate() throws(DiagnosticCaptureError) {
        try? handle?.close()
        handle = nil
        let url = configuration.directory.appendingPathComponent(String(format: "capture-%06d.jsonl", index))
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw .cannotPrepare("cannot create \(url.path)")
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw .cannotPrepare("\(error)")
        }
        currentBytes = 0
        let stale = index - configuration.maximumFiles
        if stale >= 0 {
            let old = configuration.directory.appendingPathComponent(String(format: "capture-%06d.jsonl", stale))
            try? FileManager.default.removeItem(at: old)
        }
        index += 1
    }
}
