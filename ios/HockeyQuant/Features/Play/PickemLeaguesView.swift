import SwiftUI

/// "Leagues" tab of the leaderboard — the user's private Pick'em friend groups,
/// with create/join and per-league season standings.
struct PickemLeaguesView: View {
    @Environment(AuthStore.self) private var auth
    @State private var store: PickemStore?
    @State private var creating = false
    @State private var joining = false
    @State private var nameDraft = ""
    @State private var codeDraft = ""

    var body: some View {
        Group {
            if let store {
                content(store)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if store == nil { let s = PickemStore(auth: auth); store = s; await s.load() } }
        .alert("New league", isPresented: $creating) {
            TextField("League name", text: $nameDraft)
            Button("Create") {
                let n = nameDraft.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { return }
                Task { _ = await store?.create(name: n); nameDraft = "" }
            }
            Button("Cancel", role: .cancel) { nameDraft = "" }
        } message: { Text("Invite friends with the code we generate.") }
        .alert("Join a league", isPresented: $joining) {
            TextField("Invite code", text: $codeDraft)
                .textInputAutocapitalization(.characters)
            Button("Join") {
                let c = codeDraft.trimmingCharacters(in: .whitespaces)
                guard !c.isEmpty else { return }
                Task { _ = await store?.join(code: c); codeDraft = "" }
            }
            Button("Cancel", role: .cancel) { codeDraft = "" }
        } message: { Text("Enter the code a friend shared with you.") }
    }

    @ViewBuilder
    private func content(_ store: PickemStore) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    actionButton("Create", systemImage: "plus") { creating = true }
                    actionButton("Join", systemImage: "person.badge.plus") { joining = true }
                }
                if store.loading && store.leagues.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 64) }
                } else if store.leagues.isEmpty {
                    EmptyStateView(systemImage: "person.3.fill", title: "No leagues yet",
                                   message: "Create a league and share the code, or join a friend's.")
                        .padding(.top, Theme.Spacing.xl)
                } else {
                    ForEach(store.leagues) { league in
                        NavigationLink {
                            PickemStandingsView(store: store, league: league)
                        } label: {
                            leagueCard(league)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .refreshable { await store.load() }
    }

    private func leagueCard(_ league: PickemLeague) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle().fill(Theme.Palette.accent.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.name).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    Text("\(league.memberCount) member\(league.memberCount == 1 ? "" : "s") · code \(league.inviteCode)")
                        .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: systemImage); Text(title) }
                .font(Theme.Font.headline()).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }
}

/// Per-league standings, ranked by this season's XP.
struct PickemStandingsView: View {
    let store: PickemStore
    let league: PickemLeague
    @Environment(GamificationStore.self) private var game
    @State private var detail: PickemLeagueDetail?
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if loading {
                ProgressView()
            } else if let detail, !detail.standings.isEmpty {
                ScrollView {
                    VStack(spacing: Theme.Spacing.xs) {
                        inviteHeader
                        ForEach(Array(detail.standings.enumerated()), id: \.element.id) { i, s in
                            row(s).staggeredEntrance(index: i)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            } else {
                EmptyStateView(systemImage: "trophy", title: "No standings yet",
                               message: "Make some picks this season to climb the board.")
            }
        }
        .navigationTitle(league.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { detail = await store.standings(id: league.id); loading = false }
    }

    private var inviteHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("INVITE CODE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Text(league.inviteCode).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Palette.textPrimary)
            }
            Spacer()
            ShareLink(item: "Join my HockeyQuant Pick'em league \"\(league.name)\" with code \(league.inviteCode)") {
                Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.Palette.accent)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func row(_ s: PickemStanding) -> some View {
        let isMe = s.userId == game.currentUserId
        return HStack(spacing: Theme.Spacing.sm) {
            Text("\(s.rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(s.rank <= 3 ? .white : Theme.Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(rankColor(s.rank)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(s.displayName).font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                Text("\(s.correct)/\(s.picks) · \(Int(s.accuracy.rounded()))%")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(s.seasonXp)").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Text("XP").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(isMe ? Theme.Palette.accent.opacity(0.10) : Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(isMe ? Theme.Palette.accent : Theme.Palette.border, lineWidth: isMe ? 1.5 : 1)
        )
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(hex: 0xFFD23F)
        case 2: Color(hex: 0xC0C0C0)
        case 3: Color(hex: 0xCD7F32)
        default: Theme.Palette.background
        }
    }
}
