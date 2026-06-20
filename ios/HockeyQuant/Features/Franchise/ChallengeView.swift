import SwiftUI

/// The nightly challenge: pick a real NHL team playing tonight; your dream-team's real
/// goals + a goalie boost settle against that team's real goals after the games finish.
struct ChallengeView: View {
    let store: FranchiseStore
    @State private var loading = true
    @State private var locking: String?

    private var hasTonight: Bool { store.challenge?.gameDate == store.today && !store.today.isEmpty }

    var body: some View {
        ZStack {
            Theme.backgroundView(stops: Theme.Palette.backgroundStopsPrimary).ignoresSafeArea()
            if loading && store.challenge == nil && store.challengeTeams.isEmpty {
                ProgressView().tint(Theme.Palette.accent)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        howItWorks
                        if let ch = store.challenge { resultCard(ch) }
                        tonightSection
                    }
                    .padding(Theme.Spacing.md)
                }
                .refreshable { await store.loadChallenge() }
            }
        }
        .navigationTitle("Nightly Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadChallenge(); await store.loadLineup(); loading = false }
    }

    private var howItWorks: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOW IT WORKS").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Text("Pick an NHL team playing tonight. Your lineup's real goals tonight + a goalie boost go head-to-head with that team's real goals. Win → Coins + XP.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func resultCard(_ ch: ChallengeDetail) -> some View {
        let won = ch.won ?? false
        let color: Color = ch.graded ? (won ? Theme.Palette.positive : Theme.Palette.negative) : Theme.Palette.accent
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text(ch.graded ? "LAST CHALLENGE" : "LOCKED IN").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer()
                    if let d = ch.gameDate { Text(d).font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary) }
                    if ch.graded {
                        Text(won ? "WON" : "LOST").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(color).clipShape(Capsule())
                    }
                }
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    teamColumn("Your Team", score: ch.myScore, crest: nil, mine: true)
                    Text("vs").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    teamColumn(ch.opponentTeam, score: ch.oppScore, crest: ch.opponentTeam, mine: false)
                }
                if ch.graded {
                    HStack(spacing: Theme.Spacing.md) {
                        if let c = ch.coinsAwarded { reward("bitcoinsign.circle.fill", "+\(c.asCoins)", Color(hex: 0xFFD23F)) }
                        if let x = ch.xpAwarded { reward("bolt.fill", "+\(x) XP", Theme.Palette.accent) }
                    }
                } else {
                    Text("Settles after tonight's games finish.").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private func teamColumn(_ name: String, score: Double?, crest: String?, mine: Bool) -> some View {
        VStack(spacing: 4) {
            if let crest { CrestView(abbrev: crest, size: 30) }
            else { Image(systemName: "rectangle.stack.fill").font(.system(size: 26)).foregroundStyle(Theme.Palette.accent) }
            Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
            Text(score.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(mine ? Theme.Palette.accent : Theme.Palette.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private func reward(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) { Image(systemName: icon).font(.system(size: 12)); Text(text).font(.system(size: 13, weight: .heavy, design: .rounded)) }
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var tonightSection: some View {
        if store.challengeTeams.isEmpty {
            Card {
                VStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 28)).foregroundStyle(Theme.Palette.textTertiary)
                    Text("No NHL games tonight").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    Text("Come back on a game night to challenge a team.").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                }.frame(maxWidth: .infinity)
            }
        } else if hasTonight {
            Card {
                Text("You're locked in for tonight vs \(store.challenge?.opponentTeam ?? ""). Good luck!")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary).frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("PICK TONIGHT'S OPPONENT").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 4), spacing: Theme.Spacing.sm) {
                    ForEach(store.challengeTeams, id: \.self) { team in
                        Button { Task { await lock(team) } } label: {
                            VStack(spacing: 3) {
                                CrestView(abbrev: team, size: 36)
                                Text(team).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.xs)
                            .background(Theme.Palette.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.Palette.border, lineWidth: 1))
                            .opacity(locking == team ? 0.5 : 1)
                        }.disabled(locking != nil)
                    }
                }
            }
        }
    }

    private func lock(_ team: String) async {
        locking = team
        if await store.lockChallenge(team) { Haptics.success() }
        locking = nil
    }
}
