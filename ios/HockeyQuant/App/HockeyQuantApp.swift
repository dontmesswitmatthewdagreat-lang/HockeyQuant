import SwiftUI
import GoogleSignIn

@main
struct HockeyQuantApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthStore()
    @State private var gamification = GamificationStore()
    @State private var theme = ThemeStore()
    @State private var avatar = AvatarStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(theme.generation)   // rebuild on a live team-theme change
                .environment(auth)
                .environment(gamification)
                .environment(theme)
                .environment(avatar)
                .tint(theme.accent)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
