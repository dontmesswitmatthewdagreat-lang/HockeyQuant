import SwiftUI

/// In-season hub: this week's matchup, standings, and your roster. Includes a
/// commissioner-only "simulate week" control for offseason testing.
struct FantasySeasonView: View {
    let store: FantasyStore
    let leagueId: String

    @State private var season: FantasySeasonResponse?
    @State private var tab = 0
    @State private var loading = true
    @State private var simulating = false
    @State private var working = false
    @State private var error: String?
    @Environment(\.cardSurfaceOverride) private var cardSurface

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if let season {
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        Text("This Week").tag(0)
                        Text("Standings").tag(1)
                        Text("Roster").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(Theme.Spacing.md)

                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            switch tab {
                            case 0: thisWeek(season)
                            case 1: standings(season)
                            default: roster(season)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.lg)
                    }
                    if season.league.isCommissioner {
                        commissionerBar(season)
                    }
                }
            } else if loading {
                ProgressView().tint(Theme.Palette.accent)
            } else if let error {
                ErrorStateView(message: error) { Task { await load() } }
            }
        }
        .environment(\.cardSurfaceOverride, Theme.Palette.fantasySurface)
        .task { await load() }
    }

    private func load() async {
        loading = true
        do { season = try await store.season(leagueId) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }

    // MARK: - This week

    private func thisWeek(_ s: FantasySeasonResponse) -> some View {
        let mine = s.schedule.filter { $0.involvesMe }
        let current = mine.first { $0.week == s.currentWeek } ?? mine.last
        return VStack(spacing: Theme.Spacing.md) {
            statusBanner(s)
            if s.league.isGroup && (s.league.status == "active" || s.league.status == "playoffs") {
                NavigationLink { TradesView(store: store, leagueId: leagueId, season: s) } label: { tradesRow }
                    .buttonStyle(.plain)
            }
            if let m = current {
                matchupCard(m, season: s, headline: playoffHeadline(m, s))
            }
            let played = mine.filter { $0.graded }.sorted { $0.week > $1.week }
            if !played.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("YOUR RESULTS").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    ForEach(played) { m in resultRow(m, season: s) }
                }
            } else if current?.graded == false {
                Text("No games scored yet. \(s.league.isCommissioner ? "Use “Simulate week” below to test scoring." : "Check back after games are played.")")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center).padding(.top, Theme.Spacing.sm)
            }
        }
    }

    private func matchupCard(_ m: ScheduleItem, season s: FantasySeasonResponse, headline: String) -> some View {
        let iAmA = m.memberA == s.myMemberId
        let myScore = iAmA ? m.scoreA : m.scoreB
        let oppScore = iAmA ? m.scoreB : m.scoreA
        let myTeam = iAmA ? m.aTeam : m.bTeam
        let oppTeam = iAmA ? m.bTeam : m.aTeam
        let iWon = m.graded && m.winnerMemberId == s.myMemberId
        let tie = m.graded && m.winnerMemberId == nil
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                Text(headline).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                HStack {
                    sideView(myTeam ?? "You", myScore, graded: m.graded, win: iWon)
                    Text(m.graded ? (tie ? "TIE" : (iWon ? "WON" : "LOST")) : "VS")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(m.graded ? (tie ? Theme.Palette.textTertiary : (iWon ? Theme.Palette.strong : Theme.Palette.negative)) : Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                    sideView(oppTeam ?? "—", oppScore, graded: m.graded, win: m.graded && !iWon && !tie)
                }
                if m.isGhost {
                    Text("Bye week — you play the league median score.")
                        .font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private func sideView(_ team: String, _ score: Double?, graded: Bool, win: Bool) -> some View {
        VStack(spacing: 4) {
            Text(team).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary).lineLimit(1)
            Text(graded ? String(format: "%.1f", score ?? 0) : "—")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(win ? Theme.Palette.accent : Theme.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func resultRow(_ m: ScheduleItem, season s: FantasySeasonResponse) -> some View {
        let iAmA = m.memberA == s.myMemberId
        let myScore = iAmA ? m.scoreA : m.scoreB
        let oppScore = iAmA ? m.scoreB : m.scoreA
        let oppTeam = iAmA ? m.bTeam : m.aTeam
        let iWon = m.winnerMemberId == s.myMemberId
        let tie = m.winnerMemberId == nil
        return HStack(spacing: Theme.Spacing.sm) {
            Text("W\(m.week)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary).frame(width: 30, alignment: .leading)
            Text(tie ? "T" : (iWon ? "W" : "L"))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(tie ? Theme.Palette.textTertiary : (iWon ? Theme.Palette.strong : Theme.Palette.negative))
                .frame(width: 18)
            Text("vs \(oppTeam ?? "median")").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text("\(String(format: "%.1f", myScore ?? 0)) – \(String(format: "%.1f", oppScore ?? 0))")
                .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, Theme.Spacing.xs)
        .background(cardSurface ?? Theme.Palette.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }

    // MARK: - Standings

    private func standings(_ s: FantasySeasonResponse) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(s.standings.enumerated()), id: \.element.id) { i, row in
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(i + 1)").font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textSecondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.teamName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                        Text("@\(row.username ?? "manager")").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(row.wins)–\(row.losses)\(row.ties > 0 ? "–\(row.ties)" : "")")
                            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
                        Text("\(String(format: "%.1f", row.pf)) PF").font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(row.isMe ? Theme.Palette.accent.opacity(0.10) : (cardSurface ?? Theme.Palette.surface))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(row.isMe ? Theme.Palette.accent : Color.clear, lineWidth: 1.5))
                .staggeredEntrance(index: i)
            }
        }
    }

    // MARK: - Roster

    private func roster(_ s: FantasySeasonResponse) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ForEach(s.myRoster) { slot in
                HStack(spacing: Theme.Spacing.sm) {
                    Text(FantasySlot.slotName(slot.slot)).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary).frame(width: 72, alignment: .leading)
                    if let p = slot.player {
                        CrestView(abbrev: p.team, size: 26)
                        Text(p.fullName).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                    } else {
                        Text("Empty").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, 6)
                .background(cardSurface ?? Theme.Palette.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }
        }
    }

    // MARK: - Commissioner simulate

    // MARK: - Banners

    @ViewBuilder
    private func statusBanner(_ s: FantasySeasonResponse) -> some View {
        if s.league.status == "complete" {
            let champ = s.schedule.filter { $0.graded && $0.winnerMemberId != nil }.max { $0.week < $1.week }
            let champTeam = s.standings.first { $0.memberId == champ?.winnerMemberId }?.teamName
            Card {
                VStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "trophy.fill").font(.system(size: 36)).foregroundStyle(Color(hex: 0xFFD23F))
                    Text("Champion").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                    Text(champTeam ?? "—").font(Theme.Font.title()).foregroundStyle(Theme.Palette.textPrimary)
                }.frame(maxWidth: .infinity)
            }
        } else if s.league.status == "playoffs" {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "trophy.fill").foregroundStyle(Color(hex: 0xFFD23F))
                Text("PLAYOFFS — surviving players only").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.sm).padding(.vertical, Theme.Spacing.xs)
            .background(Color(hex: 0xFFD23F).opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
    }

    private var tradesRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.left.arrow.right.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.Palette.accent)
            Text("Trades").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(Theme.Spacing.sm)
        .background(cardSurface ?? Theme.Palette.surface).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func playoffHeadline(_ m: ScheduleItem, _ s: FantasySeasonResponse) -> String {
        if s.league.status == "playoffs" || m.week > 24 { return m.graded ? "PLAYOFF RESULT" : "PLAYOFF MATCHUP" }
        return m.graded ? "WEEK \(m.week) RESULT" : "WEEK \(m.week)"
    }

    // MARK: - Commissioner controls

    private func commissionerBar(_ s: FantasySeasonResponse) -> some View {
        let status = s.league.status
        return HStack(spacing: Theme.Spacing.sm) {
            if status != "complete" {
                PressableButton(action: { simulate(week: s.currentWeek) }) {
                    barLabel(simulating ? "Simulating…" : "Sim wk \(s.currentWeek)", icon: "wand.and.stars", filled: true)
                }.disabled(simulating || working)
            }
            if status == "active" {
                PressableButton(action: { runPlayoff(start: true) }) {
                    barLabel("Start playoffs", icon: "trophy.fill", filled: false)
                }.disabled(working)
            } else if status == "playoffs" {
                PressableButton(action: { runPlayoff(start: false) }) {
                    barLabel("Advance", icon: "forward.fill", filled: false)
                }.disabled(working)
            }
        }
        .padding(Theme.Spacing.md)
    }

    private func barLabel(_ text: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon); Text(text).font(Theme.Font.caption())
        }
        .foregroundStyle(filled ? .white : Theme.Palette.accent)
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
        .background(filled ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func runPlayoff(start: Bool) {
        working = true
        Task {
            do { _ = start ? try await store.startPlayoffs(leagueId) : try await store.advancePlayoffs(leagueId); await load() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            working = false
        }
    }

    private func simulate(week: Int) {
        simulating = true
        Task {
            do { try await store.simulateWeek(leagueId, week: week); await load() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            simulating = false
        }
    }
}
