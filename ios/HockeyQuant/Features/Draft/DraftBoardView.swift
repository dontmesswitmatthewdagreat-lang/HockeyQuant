import SwiftUI

/// The live draft: who's on the clock, what just came off the board, and the
/// board itself when it's your turn.
struct DraftBoardView: View {
    let engine: DraftRoomEngine
    let onPick: (DraftBoardEntry) -> Void
    /// Trading away the pick you're on the clock with hands the turn back to an
    /// AI GM, so the room has to start picking again — without this the draft
    /// stops dead on "…is picking".
    let onTraded: () -> Void

    @State private var query = ""
    @State private var confirming: DraftBoardEntry?
    @State private var trading = false

    var body: some View {
        VStack(spacing: 0) {
            clock
            if !engine.selections.isEmpty { recentStrip }
            board
        }
        .floatingCard(item: $confirming) { entry in
            confirmCard(entry)
        }
        .sheet(isPresented: $trading) {
            DraftTradeSheet(engine: engine, onTraded: onTraded)
        }
    }

    // MARK: - On the clock

    private var clock: some View {
        let team = engine.onTheClock ?? ""
        return Card {
            VStack(spacing: Theme.Spacing.xs) {
                Text("PICK \(engine.pickNumber) OF \(engine.totalPicks)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                    .foregroundStyle(Theme.Palette.textTertiary)
                HStack(spacing: Theme.Spacing.sm) {
                    CrestView(abbrev: team, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.isUserTurn ? "You're on the clock"
                                               : engine.room.teamName(team))
                            .font(Theme.Font.headlineHeavy())
                            .foregroundStyle(engine.isUserTurn ? Theme.Palette.accent
                                                               : Theme.Palette.textPrimary)
                        Text(engine.isUserTurn
                             ? "Take the best player on your board."
                             : "\(engine.room.teamName(team)) is picking…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if !engine.isUserTurn {
                        ProgressView().tint(Theme.Palette.accent)
                    } else if let next = engine.nextUserPick, next != engine.pickNumber {
                        Text("next #\(next)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                // Trading is only coherent while you're the one holding things
                // up; between picks the clock is already moving.
                if engine.isUserTurn {
                    Button { trading = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11, weight: .bold))
                            Text("Trade this pick")
                        }
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.Palette.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    // MARK: - Recent picks

    private var recentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(engine.selections.suffix(8).reversed()) { pick in
                    HStack(spacing: 6) {
                        Text("#\(pick.overall)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textTertiary)
                        CrestView(abbrev: pick.team, size: 20)
                        Text(pick.entry.name)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(pick.byUser ? Theme.Palette.accent
                                                         : Theme.Palette.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.Palette.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        pick.byUser ? Theme.Palette.accent : Theme.Palette.border, lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .frame(height: 46)
    }

    // MARK: - Board

    private var board: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BEST AVAILABLE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Text("\(engine.available.count) left")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)

            List {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        guard engine.isUserTurn else { return }
                        confirming = entry
                    } label: {
                        row(entry, rank: index + 1)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: Theme.Spacing.md,
                                              bottom: 4, trailing: Theme.Spacing.md))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Search the board")
            .disabled(!engine.isUserTurn)
            .opacity(engine.isUserTurn ? 1 : 0.55)
        }
    }

    private var filtered: [DraftBoardEntry] {
        guard !query.isEmpty else { return engine.available }
        return engine.available.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || ($0.prospect.league ?? "").localizedCaseInsensitiveContains(query)
            || ($0.position ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private func row(_ entry: DraftBoardEntry, rank: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 22)
            headshot(entry)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let flag = entry.prospect.flag { Text(flag).font(.system(size: 12)) }
                    Text(entry.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Text(entry.prospect.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.position ?? entry.group)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Self.groupColor(entry.group)))
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    private func headshot(_ entry: DraftBoardEntry) -> some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Theme.Palette.accent.opacity(0.5), Theme.Palette.accentAlt.opacity(0.3)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            HQAsyncImage(url: entry.prospect.headshotURL, side: 38) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Text(entry.prospect.initials)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    static func groupColor(_ group: String) -> Color {
        switch group {
        case "D": Theme.Palette.defaultAccentAlt
        case "G": Color(hex: 0x8A5CF6)
        default:  Theme.Palette.accent
        }
    }

    // MARK: - Confirm

    private func confirmCard(_ entry: DraftBoardEntry) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            headshot(entry).scaleEffect(1.6).frame(height: 70)
            VStack(spacing: 2) {
                Text(entry.name)
                    .font(Theme.Font.title())
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(entry.prospect.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            if let rank = entry.prospect.ranking, let label = entry.prospect.categoryLabel {
                Text("#\(rank) — \(label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            PressableButton(action: {
                let chosen = entry
                confirming = nil
                onPick(chosen)
            }) {
                CapsuleActionLabel(title: "Draft with pick #\(engine.pickNumber)",
                                   systemImage: "checkmark", prominent: true)
            }
            Button("Not yet") { confirming = nil }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Spacing.md)
    }
}
