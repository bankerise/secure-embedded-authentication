import Foundation

/// A single telemetry event (contract §3.6, spec §20.1).
public struct SEAEvent {
    public let name: String
    public let properties: [String: String]
    public let timestamp: Date

    public init(name: String, properties: [String: String] = [:], timestamp: Date = Date()) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

/// Host-supplied telemetry sink. `record(_:)` is always called on the main
/// thread.
public protocol SEATelemetrySink: AnyObject {
    func record(_ event: SEAEvent)
}
