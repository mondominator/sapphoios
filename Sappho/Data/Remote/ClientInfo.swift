import Foundation
import UIKit

/// Identifies this app and device on every request, so the server can label
/// listening sessions ("Mondo's iPhone") instead of recording "Unknown".
///
/// The server (since !130) reads `X-Device-Name`, percent-decoding it, and
/// falls back to parsing the User-Agent. Header values must be ASCII, so any
/// non-ASCII device name (curly apostrophes, emoji, accented letters) is
/// percent-encoded.
enum ClientInfo {
    static let deviceNameHeader = "X-Device-Name"
    static let appVersionHeader = "X-App-Version"

    /// Set once at launch from the main thread (`SapphoApp.init`), because
    /// `UIDevice` is main-actor API and requests are built off main.
    /// Note: on iOS 16+ without the user-assigned-device-name entitlement
    /// the system returns the model name ("iPhone"), which is still better
    /// than "Unknown".
    static var deviceName: String = "iPhone"

    @MainActor
    static func captureDeviceName() {
        deviceName = UIDevice.current.name
    }

    /// "1.0.1 (1791300000)" from CFBundleShortVersionString and CFBundleVersion.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// ASCII letters, digits and a few safe punctuation characters pass
    /// through; everything else (including `%` itself) is percent-encoded.
    /// Deliberately not `.alphanumerics`, which admits non-ASCII letters.
    private static let headerSafe = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 -_.()"
    )

    static func encodeHeaderValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: headerSafe) ?? "iPhone"
    }

    /// Headers attached to every request the app makes to the server.
    static var headers: [String: String] {
        [
            deviceNameHeader: encodeHeaderValue(deviceName),
            appVersionHeader: appVersion
        ]
    }

    static func apply(to request: inout URLRequest) {
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }
}
