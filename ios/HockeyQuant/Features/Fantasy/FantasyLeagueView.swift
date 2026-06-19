import SwiftUI

/// Routes a private league to the right screen based on status: lobby (open) → draft
/// room (drafting) → season view (active/playoffs/complete).
struct FantasyLeagueView: View {
    let store: FantasyStore
    let leagueId: String

    @State private var detail: LeagueDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var starting = false

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            content
        }
        .environment(\.cardSurfaceOverride, Theme.Palette.fantasySurface)
        .navigationTitle(detail?.league.name ?? "League")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        do { detail = try await store.detail(leagueId) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        loading = false
    }

    @ViewBuilder
    private var content: some View {
        if loading && detail == nil {
            ProgressView().tint(Theme.Palette.accent)
        } else if let detail {
            switch detail.league.status {
            case "drafting": DraftRoomView(store: store, leagueId: leagueId)
            case "open":     lobby(detail)
            default:         FantasySeasonView(store: store, leagueId: leagueId)
            }
        } else if let error {
            ErrorStateView(message: error) { Task { await load() } }
        }
    }

    private func lobby(_ detail: LeagueDetail) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                inviteCard(detail.league)
                membersCard(detail)
                rosterFormatCard
                startSection(detail)
            }
            .padding(Theme.Spacing.md)
        }
        .refreshable { await load() }
    }

    private func inviteCard(_ league: FantasyLeagueSummary) -> some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Text("INVITE CODE").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Text(league.inviteCode)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.accent)
                    .tracking(4)
                HStack(spacing: Theme.Spacing.sm) {
                    PressableButton(action: { UIPasteboard.general.string = league.inviteCode; Haptics.success() }) {
                        pill("Copy", icon: "doc.on.doc")
                    }
                    ShareLink(item: "Join my HockeyQuant fantasy league \"\(league.name)\" with code \(league.inviteCode)") {
                        pill("Share", icon: "square.and.arrow.up")
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) { Image(systemName: icon); Text(text) }
            .font(Theme.Font.caption())
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Palette.accent.opacity(0.12)).clipShape(Capsule())
    }

    private func membersCard(_ detail: LeagueDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("MANAGERS (\(detail.members.count)/\(detail.league.maxMembers))")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                ForEach(detail.members) { m in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "person.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.Palette.accent.opacity(0.7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.teamName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                            Text("@\(m.username ?? "manager")").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        Spacer()
                        if detail.league.isCommissioner && m.isMe {
                            tag("COMMISSIONER")
                        } else if m.isMe {
                            tag("YOU")
                        }
                    }
                }
            }
        }
    }

    private func tag(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.Palette.accent.opacity(0.14)).clipShape(Capsule())
    }

    private var rosterFormatCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("ROSTER").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
                Text("2 LW · 2 RW · 2 C · 2 LHD · 2 RHD · 1 starting G · 1 backup G")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                Text("Drafted via a lottery wheel: you'll be told which position to pick each turn.")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func startSection(_ detail: LeagueDetail) -> some View {
        if detail.league.isCommissioner {
            PressableButton(action: { start() }) {
                HStack {
                    if starting { ProgressView().tint(.white) }
                    Text(detail.members.count < 2 ? "Need 2+ managers" : "Start draft")
                        .font(Theme.Font.headline())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                .background(detail.members.count >= 2 ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
            .disabled(detail.members.count < 2 || starting)
        } else {
            Text("Waiting for the commissioner to start the draft…")
                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private func start() {
        starting = true
        Task {
            do { _ = try await store.startDraft(leagueId); await load() }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            starting = false
        }
    }
}
