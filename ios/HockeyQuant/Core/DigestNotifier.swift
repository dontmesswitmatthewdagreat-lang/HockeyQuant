import Foundation
import UserNotifications

/// How often the Rapid Digest notification fires.
enum DigestFrequency: Int, CaseIterable, Identifiable {
    case sixHourly = 6
    case twiceDaily = 12
    case daily = 24
    case everyOtherDay = 48
    case weekly = 168

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .sixHourly: return "Every 6 hours"
        case .twiceDaily: return "Twice a day"
        case .daily: return "Once a day"
        case .everyOtherDay: return "Every other day"
        case .weekly: return "Once a week"
        }
    }
}

/// Delivers the Rapid Digest (the day's top key points) as a repeating local
/// notification. The toggle + frequency live in `@AppStorage`; the body is
/// refreshed with the latest key points each time the app loads a digest.
/// (Local-only for now — a future upgrade is a fresh server push from the
/// existing digest cron.)
enum DigestNotifier {
    static let enabledKey = "rapidDigestEnabled"
    static let freqKey = "rapidDigestFreqHours"
    private static let pointsKey = "rapidDigestPoints"
    private static let requestID = "rapidDigest"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var frequency: DigestFrequency {
        DigestFrequency(rawValue: UserDefaults.standard.object(forKey: freqKey) as? Int ?? 12) ?? .twiceDaily
    }

    /// Cache the latest key points (called when News loads a digest) + reschedule.
    static func updatePoints(_ points: [String]) {
        UserDefaults.standard.set(Array(points.prefix(5)), forKey: pointsKey)
        reschedule()
    }

    /// (Re)schedule the repeating notification from the cached points + settings.
    /// Called on launch, on digest load, and when the toggle/frequency change.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        guard isEnabled else { return }
        let points = UserDefaults.standard.stringArray(forKey: pointsKey) ?? []
        guard !points.isEmpty else { return }

        let interval = Double(frequency.rawValue) * 3600
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rapid Digest"
            content.body = points.prefix(4).map { "• \($0)" }.joined(separator: "\n")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
            // Fetch the center inside the closure (don't capture the non-Sendable one).
            UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
        }
    }
}
