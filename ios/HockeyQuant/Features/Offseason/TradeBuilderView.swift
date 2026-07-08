import SwiftUI

/// Build a hypothetical trade: pick two teams, select the players (and draft
/// picks) heading each way, and watch both cap sheets react before you commit.
struct TradeBuilderView: View {
    var store: OffseasonStore
    @Environment(\.dismiss) private var dismiss

    @State private var teamA = ""
    @State private var teamB = ""
    @State private var rosterA: [ContractPlayer] = []
    @State private var rosterB: [ContractPlayer] = []
    @State private var selectedA: Set<String> = []   // names leaving team A
    @State private var selectedB: Set<String> = []
    @State private var picksA: [TradePiece] = []     // picks team A sends
    @State private var picksB: [TradePiece] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        teamPickers
                        if !teamA.isEmpty { sideCard(team: teamA, roster: rosterA, selected: $selectedA, picks: $picksA, other: teamB) }
                        if !teamB.isEmpty { sideCard(team: teamB, roster: rosterB, selected: $selectedB, picks: $picksB, other: teamA) }
                        if bothChosen { capSummary }
                        completeButton
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Trade builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var bothChosen: Bool { !teamA.isEmpty && !teamB.isEmpty && teamA != teamB }

    // MARK: - Team pickers

    private var teamPickers: some View {
        HStack(spacing: Theme.Spacing.sm) {
            teamMenu(selection: $teamA, exclude: teamB, placeholder: "Team A") { new in
                selectedA = []; picksA = []
                Task { rosterA = await store.roster(for: new) }
            }
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
            teamMenu(selection: $teamB, exclude: teamA, placeholder: "Team B") { new in
                selectedB = []; picksB = []
                Task { rosterB = await store.roster(for: new) }
            }
        }
    }

    private func teamMenu(selection: Binding<String>, exclude: String,
                          placeholder: String, onPick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach((store.market?.teams ?? []).map(\.abbrev).sorted(), id: \.self) { ab in
                if ab != exclude {
                    Button(TeamInfo.lookup(ab).name) {
                        selection.wrappedValue = ab
                        onPick(ab)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if selection.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    CrestView(abbrev: selection.wrappedValue, size: 26)
                    Text(selection.wrappedValue)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.Palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
        }
    }

    // MARK: - One side of the trade

    private func sideCard(team: String, roster: [ContractPlayer],
                          selected: Binding<Set<String>>, picks: Binding<[TradePiece]>,
                          other: String) -> some View {
        SectionCard("\(team) send\(other.isEmpty ? "" : " to \(other)")") {
            VStack(spacing: Theme.Spacing.xs) {
                if roster.isEmpty {
                    LoadingShimmer(height: 80)
                } else {
                    ForEach(roster.prefix(24)) { player in
                        let unavailable = store.tradedAway(from: team).contains(player.name)
                        let isOn = selected.wrappedValue.contains(player.name)
                        Button {
                            if isOn { selected.wrappedValue.remove(player.name) }
                            else { selected.wrappedValue.insert(player.name) }
                        } label: {
                            HStack {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.textTertiary)
                                Text(player.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(unavailable ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                                    .strikethrough(unavailable)
                                Text(player.position)
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                Spacer()
                                Text(player.aav.asCapMoney)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(unavailable)
                    }
                }
                pickRow(team: team, picks: picks)
            }
        }
    }

    private func pickRow(team: String, picks: Binding<[TradePiece]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(picks.wrappedValue) { pick in
                HStack {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xFF9500))
                    Text(pick.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    Button {
                        picks.wrappedValue.removeAll { $0.id == pick.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            Menu {
                ForEach(["2026", "2027", "2028"], id: \.self) { year in
                    ForEach(["1st", "2nd", "3rd"], id: \.self) { round in
                        let label = "\(year) \(round) Round Pick (\(team))"
                        if !picks.wrappedValue.contains(where: { $0.name == label }) {
                            Button(label) {
                                picks.wrappedValue.append(TradePiece(name: label, position: "PICK", aav: 0))
                            }
                        }
                    }
                }
            } label: {
                Label("Add draft pick", systemImage: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Cap summary + commit

    private var piecesAtoB: [TradePiece] {
        rosterA.filter { selectedA.contains($0.name) }
            .map { TradePiece(name: $0.name, position: $0.position, aav: $0.aav) } + picksA
    }
    private var piecesBtoA: [TradePiece] {
        rosterB.filter { selectedB.contains($0.name) }
            .map { TradePiece(name: $0.name, position: $0.position, aav: $0.aav) } + picksB
    }

    private func spaceAfter(for team: String, out: [TradePiece], inbound: [TradePiece]) -> Double {
        let base = store.effectiveSpace(for: team) ?? 0
        return base + out.reduce(0) { $0 + $1.aav } - inbound.reduce(0) { $0 + $1.aav }
    }

    private var capSummary: some View {
        let afterA = spaceAfter(for: teamA, out: piecesAtoB, inbound: piecesBtoA)
        let afterB = spaceAfter(for: teamB, out: piecesBtoA, inbound: piecesAtoB)
        return SectionCard("Cap after trade") {
            VStack(spacing: Theme.Spacing.xs) {
                summaryRow(team: teamA, after: afterA)
                summaryRow(team: teamB, after: afterB)
                if afterA < 0 || afterB < 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("One side ends up over the cap — balance the money.")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.negative)
                }
            }
        }
    }

    private func summaryRow(team: String, after: Double) -> some View {
        HStack {
            CrestView(abbrev: team, size: 24)
            Text(team)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text(after.asCapMoney + " space")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(after < 0 ? Theme.Palette.negative : Theme.Palette.positive)
        }
    }

    private var canComplete: Bool {
        bothChosen && !(piecesAtoB.isEmpty && piecesBtoA.isEmpty)
            && spaceAfter(for: teamA, out: piecesAtoB, inbound: piecesBtoA) >= 0
            && spaceAfter(for: teamB, out: piecesBtoA, inbound: piecesAtoB) >= 0
    }

    private var completeButton: some View {
        PressableButton(action: {
            guard canComplete else { return }
            store.addTrade(teamA: teamA, teamB: teamB, aToB: piecesAtoB, bToA: piecesBtoA)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
        }) {
            CapsuleActionLabel(title: "Complete trade", systemImage: "arrow.triangle.swap", prominent: canComplete)
        }
        .disabled(!canComplete)
        .opacity(canComplete ? 1 : 0.6)
    }
}
