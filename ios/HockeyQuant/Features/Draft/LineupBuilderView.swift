import SwiftUI

/// Where your draft picks actually fit: the club's real lineup, with the players
/// you just drafted waiting to be slotted in.
///
/// The screen answers one question — "is he an NHL player *now*?" — by making
/// you push somebody down to make room for him.
struct LineupBuilderView: View {
    let team: String
    let teamName: String
    let picks: [DraftBoardEntry]

    @State private var builder: LineupBuilder?
    @State private var selected: LineupBuilder.Skater?
    @State private var loading = true
    @State private var errorMessage: String?

    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView()
            content
        }
        .navigationTitle("Lineup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 96) }
                }
                .padding(Theme.Spacing.md)
            }
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if let builder {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    header(builder)
                    picksStrip(builder)
                    unitSection("Forwards", group: .forward, units: 1...4, builder: builder)
                    unitSection("Defense", group: .defense, units: 1...3, builder: builder)
                    unitSection("Goaltending", group: .goalie, units: 1...2, builder: builder)
                    resetButton(builder)
                }
                .padding(Theme.Spacing.md)
            }
        }
    }

    // MARK: - Header

    private func header(_ builder: LineupBuilder) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: team, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(teamName)
                        .font(Theme.Font.headlineHeavy())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Lines are built by cap value. Drop a pick in and see who he bumps.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Your picks

    private func picksStrip(_ builder: LineupBuilder) -> some View {
        SectionCard("Your draft picks") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if builder.picks.isEmpty {
                    Text("You didn't draft anyone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                ForEach(builder.picks) { pick in
                    pickRow(pick, builder: builder)
                }
                if selected != nil {
                    Text("Now tap a slot below to try him there.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
        }
    }

    private func pickRow(_ pick: LineupBuilder.Skater, builder: LineupBuilder) -> some View {
        let isSelected = selected?.id == pick.id
        let placed = builder.verdict(for: pick)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selected = isSelected ? nil : pick
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                face(pick, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(placed ?? "Not in the lineup")
                        .font(.system(size: 11, weight: placed == nil ? .regular : .semibold))
                        .foregroundStyle(placed == nil ? Theme.Palette.textTertiary
                                                       : Theme.Palette.positive)
                }
                Spacer(minLength: 0)
                Text(isSelected ? "Tap a slot" : "Place")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? .white : Theme.Palette.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(isSelected ? Theme.Palette.accent
                                                          : Theme.Palette.accent.opacity(0.14)))
            }
            .padding(.vertical, 4)
            // Without this the row only hits on its text and pill — a tap in the
            // gap between them falls through and the row looks dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Units

    private func unitSection(_ title: String, group: LineupBuilder.Slot.Group,
                             units: ClosedRange<Int>, builder: LineupBuilder) -> some View {
        SectionCard(title) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(units, id: \.self) { unit in
                    unitRow(unit, group: group, builder: builder)
                }
            }
        }
    }

    private func unitRow(_ unit: Int, group: LineupBuilder.Slot.Group,
                         builder: LineupBuilder) -> some View {
        let entries = builder.players(inUnit: unit, group: group)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(unitLabel(unit, group: group))
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                if group != .goalie {
                    Text(builder.unitValue(unit, group: group).asCapMoney)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(entries, id: \.slot.id) { entry in
                    slotCell(entry.slot, skater: entry.skater, builder: builder)
                }
            }
        }
    }

    private func unitLabel(_ unit: Int, group: LineupBuilder.Slot.Group) -> String {
        switch group {
        case .forward: "LINE \(unit)"
        case .defense: "PAIR \(unit)"
        case .goalie: unit == 1 ? "STARTER" : "BACKUP"
        }
    }

    private func slotCell(_ slot: LineupBuilder.Slot, skater: LineupBuilder.Skater?,
                          builder: LineupBuilder) -> some View {
        let eligible = selected.map { builder.eligibleSlots(for: $0).contains(slot) } ?? false
        return Button {
            guard let picked = selected else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                builder.assign(picked, to: slot)
                selected = nil
            }
            Haptics.success()
        } label: {
            VStack(spacing: 4) {
                Text(slot.label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textTertiary)
                if let skater {
                    face(skater, size: 32)
                    Text(skater.name)
                        .font(.system(size: 11, weight: skater.isDraftPick ? .heavy : .semibold,
                                      design: .rounded))
                        .foregroundStyle(skater.isDraftPick ? Theme.Palette.accent
                                                            : Theme.Palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Circle().fill(Theme.Palette.border.opacity(0.5)).frame(width: 32, height: 32)
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(eligible ? Theme.Palette.accent
                                  : (skater?.isDraftPick == true ? Theme.Palette.accent.opacity(0.5)
                                                                 : Theme.Palette.border),
                                  lineWidth: eligible ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(selected == nil || !eligible)
        .opacity(selected != nil && !eligible ? 0.45 : 1)
    }

    private func face(_ skater: LineupBuilder.Skater, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Theme.Palette.accent.opacity(0.45), Theme.Palette.accentAlt.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            HQAsyncImage(url: skater.headshotURL, side: size) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Text(skater.initials)
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(
            skater.isDraftPick ? Theme.Palette.accent : Theme.Palette.border,
            lineWidth: skater.isDraftPick ? 2 : 1))
    }

    private func resetButton(_ builder: LineupBuilder) -> some View {
        PressableButton(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                builder.autoFill()
                selected = nil
            }
        }) {
            CapsuleActionLabel(title: "Reset to the real lineup",
                               systemImage: "arrow.counterclockwise")
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let roster = try await api.fantasyPlayers(team: team, limit: 60)
            guard !roster.isEmpty else {
                errorMessage = "No roster on file for \(teamName)."
                return
            }
            builder = LineupBuilder(roster: roster, draftPicks: picks)
            errorMessage = nil
        } catch {
            Log.error("lineup roster", error)
            errorMessage = error.localizedDescription
        }
    }
}
