import SwiftUI

/// Top-level gate: splash while initializing → Welcome/Auth if signed out →
/// Setup wizard if onboarding incomplete → the main tab app.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Group {
            if auth.isInitializing {
                SplashView()
            } else if !auth.isSignedIn {
                WelcomeView()
            } else if !auth.onboardingComplete {
                SetupWizardView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: auth.isInitializing)
        .animation(.easeInOut(duration: 0.3), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.3), value: auth.onboardingComplete)
        // The team theme forces a light or dark scheme (by the secondary's
        // brightness) so system surfaces + dynamic text colors stay legible.
        .preferredColorScheme(theme.forcedScheme)
        // Theme follows the favorite team.
        .task(id: auth.favoriteTeam) { theme.follow(team: auth.favoriteTeam) }
    }
}

/// The signed-in, onboarded app — bottom-tab IA.
struct MainTabView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            NewsView()
                .tabItem { Label("News", systemImage: "newspaper") }

            PlayView()
                .tabItem { Label("Play", systemImage: "gamecontroller") }

            ModelsView()
                .tabItem { Label("Models", systemImage: "slider.horizontal.3") }

            StatsView()
                .tabItem { Label("Statistics", systemImage: "chart.bar") }
        }
        .task {
            // Ask for notification permission + register for push, then upload the
            // device token so the server can ping you when it's your draft pick.
            PushManager.shared.requestAuthorization()
            PushManager.shared.setAuth(await auth.accessToken())
        }
    }
}

/// Branded launch splash shown while auth state resolves.
struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.Palette.brandRed.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "hockey.puck.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                Text("HockeyQuant")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                ProgressView().tint(.white).padding(.top, Theme.Spacing.sm)
            }
        }
    }
}
