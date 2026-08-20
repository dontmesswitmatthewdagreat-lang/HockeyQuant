import SwiftUI

/// How the draft went: your haul first, then the verdict against the real first
/// round, then everyone else's.
struct DraftResultsView: View {
    let engine: DraftRoomEngine
    let onRestart: () -> Void

    @State private var showFullRound = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                header
                if let verdict = engine.verdict() { verdictCard(verdict) }
                yourPicks
                if !engine.userSelections.isEmpty { lineupLink }
                fullRound
                PressableButton(action: onRestart) {
                    CapsuleActionLabel(title: "Draft again", systemImage: "arrow.counterclockwise")
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var header: some View {
        Card {
            VStack(spacing: Theme.Spacing.xs) {
                CrestView(abbrev: engine.userTeam, size: 54)
                Text("\(engine.room.teamName(engine.userTeam)) — draft complete")
                    .font(Theme.Font.headlineHeavy())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(engine.userSelections.count) pick\(engine.userSelections.count == 1 ? "" : "s") in the \(engine.room.yearLabel) first round")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Verdict (re-draft only)

    private func verdictCard(_ verdict: DraftRoomEngine.Verdict) -> some View {
        SectionCard("Against the real draft") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(edgeText(verdict.averageEdge))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(verdict.averageEdge >= 0 ? Theme.Palette.positive
                                                                  : Theme.Palette.negative)
                    Text("average slots of value")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(summary(verdict))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
                HStack(spacing: Theme.Spacing.md) {
                    tally("\(verdict.steals)", "steals", Theme.Palette.positive)
                    tally("\(verdict.reaches)", "reaches", Theme.Palette.negative)
                    tally("\(verdict.graded)", "graded", Theme.Palette.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func tally(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func edgeText(_ edge: Double) -> String {
        String(format: edge >= 0 ? "+%.1f" : "%.1f", edge)
    }

    private func summary(_ verdict: DraftRoomEngine.Verdict) -> String {
        if verdict.averageEdge > 1 {
            return "You landed players the league took earlier than you did — on this board, that's value."
        }
        if verdict.averageEdge < -1 {
            return "You went earlier on your picks than the league did. Reaches, if you trust the real draft."
        }
        return "Your picks landed about where the league took them."
    }

    // MARK: - Picks

    private var yourPicks: some View {
        SectionCard("Your picks") {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(engine.userSelections) { pick in
                    VStack(alignment: .leading, spacing: 6) {
                        pickRow(pick, highlight: true)
                        if engine.room.isRedraftMode { comparison(pick) }
                    }
                }
            }
        }
    }

    /// What actually happened with that pick and that player — the two halves of
    /// the comparison people argue about.
    @ViewBuilder
    private func comparison(_ pick: DraftRoomEngine.Selection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let real = engine.actualPick(at: pick.overall), real.player != pick.entry.name {
                Label("\(real.team ?? "") actually took \(real.player ?? "—") here",
                      systemImage: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            if let actual = pick.entry.actual {
                let diff = actual.overall - pick.overall
                Label(diff == 0
                      ? "Went exactly here in real life"
                      : (diff > 0
                         ? "Really went #\(actual.overall) to \(actual.team ?? "—") — \(diff) slots later"
                         : "Really went #\(actual.overall) to \(actual.team ?? "—") — \(-diff) slots earlier"),
                      systemImage: diff > 0 ? "arrow.down.right" : (diff < 0 ? "arrow.up.right" : "equal"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(diff > 0 ? Theme.Palette.positive
                                              : (diff < 0 ? Theme.Palette.negative
                                                          : Theme.Palette.textTertiary))
            } else {
                Label("Undrafted in real life", systemImage: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(.leading, 30)
    }

    /// Drafting a player and seeing where he'd actually dress are the same
    /// question asked twice, so the lineup is one tap from the haul.
    private var lineupLink: some View {
        NavigationLink {
            LineupBuilderView(team: engine.userTeam,
                              teamName: engine.room.teamName(engine.userTeam),
                              picks: engine.userSelections.map(\.entry))
        } label: {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Palette.accent.opacity(0.16))
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where do they fit?")
                            .font(Theme.Font.headlineHeavy())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("Slot your picks into the real lineup and see who they push down.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var fullRound: some View {
        SectionCard("Full first round", accessory: AnyView(
            Button(showFullRound ? "Hide" : "Show") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showFullRound.toggle()
                }
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.Palette.accent)
        )) {
            if showFullRound {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(engine.selections) { pick in
                        pickRow(pick, highlight: pick.byUser)
                    }
                }
            } else {
                Text("Every pick the room made, in order.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func pickRow(_ pick: DraftRoomEngine.Selection, highlight: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("#\(pick.overall)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(highlight ? Theme.Palette.accent : Theme.Palette.textTertiary)
                .frame(width: 30, alignment: .leading)
            CrestView(abbrev: pick.team, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let flag = pick.entry.prospect.flag { Text(flag).font(.system(size: 11)) }
                    Text(pick.entry.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Text(pick.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(pick.entry.position ?? pick.entry.group)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(DraftBoardView.groupColor(pick.entry.group)))
        }
    }
}
