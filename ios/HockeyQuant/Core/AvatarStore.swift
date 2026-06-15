import SwiftUI
import Observation

/// The user's profile photo, stored on-device (documents dir). Shown in the
/// Profile header and the persistent top-right avatar. Cloud sync can come later
/// when we add photo storage to the backend.
@MainActor
@Observable
final class AvatarStore {
    private(set) var image: UIImage?

    private let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("profile_avatar.jpg")

    init() {
        if let data = try? Data(contentsOf: fileURL) {
            image = UIImage(data: data)
        }
    }

    func set(_ img: UIImage) {
        image = img
        if let data = img.jpegData(compressionQuality: 0.85) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}
