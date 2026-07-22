import Foundation
import React
import SEACore

/// Bridges SEACore's §20 telemetry sink and two demo-harness utilities
/// (purge web data, clipboard copy) to JS. This is presentation-adjacent
/// debug tooling, not part of the §7.1 SecureAuthenticationView contract —
/// kept in its own native module rather than the Fabric view.
@objc(SeaTelemetryEmitter)
public class SeaTelemetryEmitter: RCTEventEmitter, SEATelemetrySink {
    private var hasListeners = false

    override public static func requiresMainQueueSetup() -> Bool { true }

    override public func supportedEvents() -> [String]! {
        ["SeaTelemetryEvent"]
    }

    override public func startObserving() {
        hasListeners = true
        SEASession.telemetrySink = self
    }

    override public func stopObserving() {
        hasListeners = false
        SEASession.telemetrySink = nil
    }

    // SEATelemetrySink — contract guarantees this is called on the main thread.
    public func record(_ event: SEAEvent) {
        guard hasListeners else { return }
        sendEvent(withName: "SeaTelemetryEvent", body: [
            "name": event.name,
            "properties": event.properties,
            "timestampMs": event.timestamp.timeIntervalSince1970 * 1000,
        ])
    }

    @objc(copyToClipboard:)
    public func copyToClipboard(_ text: String) {
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
        }
    }

    @objc(purgeWebData:rejecter:)
    public func purgeWebData(
        resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        DispatchQueue.main.async {
            SEASession.purgeWebData {
                resolve(nil)
            }
        }
    }
}
