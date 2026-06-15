import SwiftUI

/// First-run setup wizard: username → favorite team (+ team colors) → how it
/// works → Get Started. Shown once per account (gated by `auth.onboardingComplete`).
struct SetupWizardView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ThemeStore.self) private var theme

    @State private var step = 0
    @State private var username = ""
    @State private var selectedTeam: String?
    @State private var useTeamColors = false
    @State private var saving = false

    private let stepCount = 5  // username, team, 3 how-it-works

    private var canAdvance: Bool {
        switch step {
        case 0: return !username.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            VStack(spacing: 0) {
                progressDots
                TabView(selection: $step) {
                    usernameStep.tag(0)
                    teamStep.tag(1)
                    infoStep(icon: "calendar", title: "The Schedule", body: "Every game, every day — the model's pick, win probability, projected score, and sportsbook odds for context. Tap a game for the full breakdown.").tag(2)
                    infoStep(icon: "gamecontroller.fill", title: "Call the Game", body: "Make your own daily picks in Play. Build streaks, earn XP, unlock badges, climb the leaderboard, and chase your GM-track tier all season.").tag(3)
                    infoStep(icon: "slider.horizontal.3", title: "Build & Compete", body: "Tune your own prediction model in Models and compete on the leaderboard. Track the official model's accuracy in Statistics.").tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: step)
                controls
            }
        }
        .onAppear {
            username = auth.username ?? ""
            selectedTeam = auth.favoriteTeam
            useTeamColors = theme.useTeamColors
            applyPreview()
        }
    }

    // MARK: - Progress

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Theme.Palette.accent : Theme.Palette.border)
                    .frame(width: i == step ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.3), value: step)
            }
        }
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Steps

    private var usernameStep: some View {
        stepScaffold(icon: "person.crop.circle.fill", title: "Pick a username", subtitle: "This is how you'll show up on leaderboards.") {
            VStack(spacing: Theme.Spacing.sm) {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Theme.Font.headline())
                    .padding(Theme.Spacing.md)
                    .background(Theme.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.Palette.border, lineWidth: 1))
            }
        }
    }

    private var teamStep: some View {
        stepScaffold(icon: "star.fill", title: "Your team?", subtitle: "Pick a favorite — optionally make its colors your app theme.") {
            VStack(spacing: Theme.Spacing.md) {
                Toggle(isOn: $useTeamColors) {
                    Text("Use my team's colors")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                .tint(Theme.Palette.accent)
                .onChange(of: useTeamColors) { _, _ in applyPreview() }
                .disabled(selectedTeam == nil)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 5), spacing: Theme.Spacing.sm) {
                        ForEach(sortedTeams, id: \.abbrev) { team in
                            Button {
                                selectedTeam = (selectedTeam == team.abbrev) ? nil : team.abbrev
                                applyPreview()
                                Haptics.tap()
                            } label: {
                                CrestView(abbrev: team.abbrev, size: 48)
                                    .overlay(Circle().stroke(Theme.Palette.accent, lineWidth: selectedTeam == team.abbrev ? 3 : 0))
                                    .scaleEffect(selectedTeam == team.abbrev ? 1.08 : 1)
                                    .animation(.spring(response: 0.3), value: selectedTeam)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private func infoStep(icon: String, title: String, body: String) -> some View {
        stepScaffold(icon: icon, title: title, subtitle: nil) {
            Text(body)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.md)
        }
    }

    private func stepScaffold<Content: View>(icon: String, title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.Palette.accent.opacity(0.16)).frame(width: 88, height: 88)
                    Image(systemName: icon).font(.system(size: 38)).foregroundStyle(Theme.Palette.accent)
                }
                .padding(.top, Theme.Spacing.lg)
                Text(title)
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
                content()
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if step > 0 {
                PressableButton(action: { withAnimation { step -= 1 } }) {
                    Text("Back")
                        .font(Theme.Font.headline())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
            }
            PressableButton(action: advance) {
                HStack {
                    if saving { ProgressView().tint(.white) }
                    Text(step == stepCount - 1 ? "Get Started" : "Continue")
                        .font(Theme.Font.headline())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(canAdvance ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .disabled(!canAdvance || saving)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Logic

    private var sortedTeams: [TeamInfo] {
        TeamInfo.all.values.sorted { $0.name < $1.name }
    }

    private func applyPreview() {
        theme.preview(team: (useTeamColors && selectedTeam != nil) ? selectedTeam : nil)
    }

    private func advance() {
        guard canAdvance else { return }
        if step < stepCount - 1 {
            withAnimation { step += 1 }
            return
        }
        // Final step → persist everything.
        saving = true
        Task {
            defer { saving = false }
            let name = username.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name != auth.username { try? await auth.updateUsername(name) }
            await auth.updateFavoriteTeam(selectedTeam)
            theme.setTeamColors(enabled: useTeamColors && selectedTeam != nil, team: selectedTeam)
            auth.markOnboarded()
        }
    }
}
