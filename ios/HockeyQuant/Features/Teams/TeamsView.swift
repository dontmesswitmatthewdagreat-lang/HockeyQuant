import SwiftUI

/// Team browser grouped by division. Pushed within the Stats navigation stack.
struct TeamsView: View {
    @State private var model = TeamsViewModel()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            content
        }
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .loading = model.state { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<6, id: \.self) { _ in LoadingShimmer(height: 56) }
                }
                .padding(Theme.Spacing.md)
            }
        case .error(let message):
            ErrorStateView(message: message) { Task { await model.load() } }
        case .loaded(let teams):
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    ForEach(model.grouped(teams), id: \.division) { group in
                        divisionSection(group.division, teams: group.teams)
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    private func divisionSection(_ division: String, teams: [TeamListItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(division) · \(teams.first?.conference ?? "")")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.leading, Theme.Spacing.xs)
            Card(padding: Theme.Spacing.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                        NavigationLink {
                            TeamDetailView(abbrev: team.abbrev)
                        } label: {
                            teamRow(rank: index + 1, team: team)
                        }
                        .buttonStyle(.plain)
                        if team.id != teams.last?.id {
                            Divider().overlay(Theme.Palette.border).padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private func teamRow(rank: Int, team: TeamListItem) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 16)
            CrestView(abbrev: team.abbrev, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(team.info.name)
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(team.record)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(team.points)")
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("PTS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }
}
