import Foundation
import OSLog

/// Centralized DEV logging so every pipeline stage (network, decode, auth,
/// grading) is diagnosable and silent failures are impossible. Mirrors the
/// "log at every stage, never swallow errors" rule from the plan.
enum Log {
    private static let net = Logger(subsystem: "com.hockeyquant.app", category: "network")
    private static let app = Logger(subsystem: "com.hockeyquant.app", category: "app")

    static func request(_ method: String, _ url: URL) {
        net.debug("→ \(method, privacy: .public) \(url.absoluteString, privacy: .public)")
    }

    static func response(_ status: Int, _ url: URL, bytes: Int) {
        net.debug("← \(status, privacy: .public) (\(bytes, privacy: .public) bytes) \(url.absoluteString, privacy: .public)")
    }

    static func error(_ message: String, _ error: Error? = nil) {
        if let error {
            net.error("✗ \(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            net.error("✗ \(message, privacy: .public)")
        }
    }

    static func info(_ message: String) {
        app.info("\(message, privacy: .public)")
    }
}
