import SwiftUI

/// Signed-out landing: branded hero + the email/Google/Apple auth form.
struct WelcomeView: View {
    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                hero
                AuthView()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "hockey.puck.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text("HockeyQuant")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("NHL predictions · your picks · your models")
                .font(Theme.Font.caption())
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.bottom, Theme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [Theme.Palette.brandRed, Theme.Palette.brandRed.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
}
