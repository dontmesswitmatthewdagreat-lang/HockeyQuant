import SwiftUI

/// Persistent top-right avatar — tap to open the Profile sheet. Shows the user's
/// initial (generated avatar; real photos could come later).
struct AvatarButton: View {
    @Environment(AuthStore.self) private var auth
    @Environment(AvatarStore.self) private var avatar
    @State private var showing = false

    private var initial: String {
        let name = (auth.username ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "" : String(name.first!).uppercased()
    }

    var body: some View {
        Button { showing = true } label: {
            AvatarView(image: avatar.image, initial: initial, size: 30)
        }
        .accessibilityLabel("Profile")
        .sheet(isPresented: $showing) {
            ProfileView(onDone: { showing = false })
                .environment(auth)
                .environment(avatar)
        }
    }
}

/// The avatar visual — the user's photo if set, else their initial / a person icon.
struct AvatarView: View {
    let image: UIImage?
    let initial: String
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(Theme.Palette.accent)
                if initial.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
