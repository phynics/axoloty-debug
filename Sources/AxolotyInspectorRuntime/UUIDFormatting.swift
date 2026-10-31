// Copyright (c) 2026 Atakan DULKER. Licensed under the MIT License.

import AxolotyWire

/// Formats Axoloty identifiers for inspector output.
///
/// Core 0.10 made its internal `CoatyRoute.uuidString` package-private, so the
/// inspector formats identifiers through the public wire `TopicBuilder`, the
/// same encoder Core used.
enum InspectorUUID {
    /// Returns the 36-character lowercase hyphenated form of `value`.
    ///
    /// - Parameter value: The UUID to format.
    /// - Returns: For example `0a1b2c3d-4e5f-4061-8293-a4b5c6d7e8f9`.
    static func string(_ value: UUID16) -> String {
        var bytes = [UInt8](repeating: 0, count: 36)
        bytes.withUnsafeMutableBufferPointer { output in
            var builder = TopicBuilder(buffer: output.baseAddress!, capacity: output.count)
            guard (try? builder.writeSourceId(value)) != nil else {
                preconditionFailure("UUID storage capacity calculation is invalid")
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
