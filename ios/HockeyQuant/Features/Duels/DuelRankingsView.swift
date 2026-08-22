import SwiftUI

/// The ranked ladder: every GM who has played a duel, by Elo rating.
///
/// Rating is the headline because it's what matchmaking pairs on — a 12-4
/// record against the bottom of the ladder is worth less than 8-8 at the top,
/// and showing the record next to the rating is what makes that legible.
struct DuelRankingsView: View {
    @Environment(AuthStore.self) private var auth

    @State private var rankings: [DuelRanking] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.backgroundView()
            content
        }
        .navigationTitle("Ranked Ladder")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && rankings.isEmpty {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<8, id: \.self) { _ in LoadingShimmer(height: 64) }
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage, rankings.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if rankings.isEmpty {
            EmptyStateView(
                systemImage: "trophy",
                title: "Nobody's ranked yet",
                message: "Ratings appear once the first duels are graded. Join a queue to be in the first batch."
            )
        } else {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    if let me { standingCard(me) }
                    ForEach(Array(rankings.enumerated()), id: \.element.id) { index, row in
                        rankRow(row, rank: row.rank ?? index + 1)
                            .staggeredEntrance(index: index)
                    }
                    Text("Everyone starts at 1000. A win takes rating from your opponent in proportion to how unlikely it was.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    // MARK: - Your standing

    private func standingCard(_ row: DuelRanking) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR STANDING")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text(row.rank.map { "#\($0)" } ?? "Unranked")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.accent)
                    Text(recordLine(row))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(row.rating)")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("rating")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if let streak = row.streakLabel {
                        StatusPill(text: streak,
                                   color: row.streak > 0 ? Theme.Palette.positive : Theme.Palette.negative)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func rankRow(_ row: DuelRanking, rank: Int) -> some View {
        let isMe = row.userId.lowercased() == auth.userId?.lowercased()
        return Card {
            HStack(spacing: Theme.Spacing.sm) {
                rankBadge(rank)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.username ?? "GM")
                        .font(Theme.Font.headline())
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(recordLine(row))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if let streak = row.streakLabel {
                    StatusPill(text: streak,
                               color: row.streak > 0 ? Theme.Palette.positive : Theme.Palette.negative)
                }
                // Ratings are grouped ("1,016") by Text's localized interpolation,
                // so the column has to fit four digits plus a separator.
                Text("\(row.rating)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isMe ? Theme.Palette.accent : Theme.Palette.textPrimary)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(isMe ? Theme.Palette.accent : Color.clear, lineWidth: 1.5)
        )
    }

    private func rankBadge(_ rank: Int) -> some View {
        let color: Color = switch rank {
        case 1: Color(hex: 0xFFD23F)
        case 2: Color(hex: 0xC0C0C0)
        case 3: Color(hex: 0xCD7F32)
        default: Theme.Palette.textTertiary
        }
        return Text("\(rank)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(rank <= 3 ? .white : Theme.Palette.textSecondary)
            .frame(width: 28, height: 28)
            .background(rank <= 3 ? color : Theme.Palette.background)
            .clipShape(Circle())
    }

    private func recordLine(_ row: DuelRanking) -> String {
        let record = row.ties > 0 ? "\(row.wins)-\(row.losses)-\(row.ties)" : "\(row.wins)-\(row.losses)"
        return "\(record) · \(row.duelsPlayed) duel\(row.duelsPlayed == 1 ? "" : "s")"
    }

    private var me: DuelRanking? {
        // Postgres ids are lowercase, AuthStore's are uppercased.
        guard let uid = auth.userId?.lowercased() else { return nil }
        return rankings.first { $0.userId.lowercased() == uid }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            rankings = try await APIClient().duelRankings()
            errorMessage = nil
        } catch {
            Log.error("duel rankings", error)
            errorMessage = error.localizedDescription
        }
    }
}
