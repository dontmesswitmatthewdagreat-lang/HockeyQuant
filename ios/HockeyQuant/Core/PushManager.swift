import SwiftUI
import UIKit
import UserNotifications

/// Receives the APNs device token from the system.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Log.info("APNs device token received")
        Task { @MainActor in PushManager.shared.setDeviceToken(hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on free signing / simulators without push entitlement.
        Log.error("Remote notification registration failed", error)
    }
}

/// Requests notification permission, registers for remote push, and uploads the
/// device token to the backend so the server can notify "you're on the clock".
/// Push only *delivers* once enrolled in the paid Apple Developer Program with an
/// APNs key + the aps-environment entitlement — this plumbing is ready before then.
@MainActor
final class PushManager {
    static let shared = PushManager()

    private let api = APIClient(environment: .production)
    private var deviceToken: String?
    private var accessToken: String?
    private var uploaded = false

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func setDeviceToken(_ token: String) {
        deviceToken = token
        Task { await upload() }
    }

    func setAuth(_ token: String?) {
        accessToken = token
        Task { await upload() }
    }

    private func upload() async {
        guard let deviceToken, let accessToken, !uploaded else { return }
        do {
            try await api.registerDeviceToken(deviceToken, authToken: accessToken)
            uploaded = true
            Log.info("Device token registered with backend")
        } catch {
            Log.error("Device token upload failed", error)
        }
    }
}
