import SwiftUI

/// Sign a free agent: pick the destination team, dial in term + AAV, and see
/// the team's cap space react live. Signing is blocked when it busts the cap.
struct SignPlayerSheet: View {
    var store: OffseasonStore
    let agent: FreeAgent
    @Environment(\.dismiss) private var dismiss

    @State private var team: String = ""
    @State private var years: Double = 3
    @State private var aav: Double = 3_000_000

    private var spaceBefore: Double? { team.isEmpty ? nil : store.effectiveSpace(for: team) }
    private var spaceAfter: Double? { spaceBefore.map { $0 - aav } }
    private var overCap: Bool { (spaceAfter ?? 0) < 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Text("SIGN FREE AGENT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                header
                teamPicker
                contractCard
                if !team.isEmpty { capCard }
                signButton
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 620)
        .onAppear {
            if let prev = agent.prevAav { aav = min(max(prev, 775_000), 16_000_000) }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CrestView(abbrev: agent.prevTeam ?? "?", size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: 6) {
                    Text([agent.position, agent.age.map { "\($0) yrs" }, agent.prevTeam.map { "last: \($0)" }]
                        .compactMap(\.self).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.textSecondary)
                    StatusPill(text: agent.type,
                               color: agent.type == "UFA" ? Theme.Palette.accent : Theme.Palette.moderate)
                }
                if let prev = agent.prevAav {
                    Text("Previous contract: \(prev.asCapMoney)/yr")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer()
        }
    }

    private var teamPicker: some View {
        SectionCard("Destination") {
            Menu {
                ForEach(sortedTeams, id: \.abbrev) { t in
                    Button {
                        team = t.abbrev
                    } label: {
                        Label("\(TeamInfo.lookup(t.abbrev).name)  ·  \((store.effectiveSpace(for: t.abbrev) ?? t.capSpace).asCapMoney) space",
                              systemImage: team == t.abbrev ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if team.isEmpty {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.Palette.accent)
                        Text("Choose a team")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    } else {
                        CrestView(abbrev: team, size: 30)
                        Text(TeamInfo.lookup(team).name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var sortedTeams: [TeamCapInfo] {
        (store.market?.teams ?? []).sorted {
            store.effectiveSpace(for: $0.abbrev) ?? 0 > store.effectiveSpace(for: $1.abbrev) ?? 0
        }
    }

    private var contractCard: some View {
        SectionCard("Contract") {
            VStack(spacing: Theme.Spacing.md) {
                VStack(spacing: 4) {
                    HStack {
                        Text("Term")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        Text("\(Int(years)) year\(Int(years) == 1 ? "" : "s")")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    Slider(value: $years, in: 1...8, step: 1)
                }
                VStack(spacing: 4) {
                    HStack {
                        Text("AAV (cap hit / year)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        Text(aav.asCapMoney)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    Slider(value: $aav, in: 775_000...16_000_000, step: 25_000)
                }
                Text("Total: \((aav * years).asCapMoney) over \(Int(years)) year\(Int(years) == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                if let fair = agent.fairAav {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Market value: \(fair.asCapMoney)/yr")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        verdictPill(liveVerdict(fair: fair))
                    }
                    .padding(Theme.Spacing.xs)
                    .background(Theme.Palette.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                }
            }
        }
    }

    private func liveVerdict(fair: Double) -> String {
        let prem = (aav - fair) / fair
        return prem < -0.15 ? "steal" : (prem > 0.15 ? "overpay" : "fair")
    }

    private var capCard: some View {
        SectionCard("Cap impact — \(team)") {
            VStack(spacing: Theme.Spacing.xs) {
                capRow("Space today", spaceBefore ?? 0, neutral: true)
                capRow("After signing", spaceAfter ?? 0, neutral: false)
                if overCap {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("This deal busts the cap — lower the AAV or pick a team with more room.")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.negative)
                }
            }
        }
    }

    private func capRow(_ label: String, _ value: Double, neutral: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value.asCapMoney)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(neutral ? Theme.Palette.textPrimary
                                         : (value < 0 ? Theme.Palette.negative : Theme.Palette.positive))
        }
    }

    private var signButton: some View {
        PressableButton(action: {
            guard !team.isEmpty, !overCap else { return }
            store.addSigning(agent: agent, team: team, aav: aav, years: Int(years))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
        }) {
            CapsuleActionLabel(
                title: team.isEmpty ? "Choose a team first" : (overCap ? "Over the cap" : "Sign \(agent.name.components(separatedBy: " ").last ?? agent.name)"),
                systemImage: "signature",
                prominent: !team.isEmpty && !overCap)
        }
        .disabled(team.isEmpty || overCap)
        .opacity(team.isEmpty || overCap ? 0.6 : 1)
    }
}

/// One team's cap sheet: live space after your moves, the real roster (lazy
/// loaded), and a jump into the trade builder.
struct TeamCapSheet: View {
    var store: OffseasonStore
    let team: TeamCapInfo
    let onTrade: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var roster: [ContractPlayer] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Spacing.md) {
                        header
                        Button(action: onTrade) {
                            CapsuleActionLabel(title: "Build a trade", systemImage: "arrow.triangle.swap", prominent: true)
                        }
                        .buttonStyle(.plain)
                        rosterCard
                    }
                    .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle(TeamInfo.lookup(team.abbrev).name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            roster = await store.roster(for: team.abbrev)
            loading = false
        }
    }

    private var header: some View {
        let space = store.effectiveSpace(for: team.abbrev) ?? team.capSpace
        let hit = store.effectiveHit(for: team.abbrev) ?? team.capHit
        let ceiling = store.market?.capCeiling ?? 104_000_000
        return SectionCard("Cap sheet") {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    CrestView(abbrev: team.abbrev, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(space.asCapMoney + " space")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(space < 0 ? Theme.Palette.negative : Theme.Palette.positive)
                        Text("\(hit.asCapMoney) committed of \(ceiling.asCapMoney)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.border.opacity(0.5))
                        Capsule()
                            .fill(hit > ceiling ? Theme.Palette.negative : TeamInfo.lookup(team.abbrev).color)
                            .frame(width: geo.size.width * min(hit / ceiling, 1))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private var rosterCard: some View {
        SectionCard("Contracts (\(roster.count))") {
            if loading {
                LoadingShimmer(height: 120)
            } else if roster.isEmpty {
                Text("Roster unavailable right now.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(roster) { player in
                        HStack {
                            Text(player.position)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(TeamInfo.lookup(team.abbrev).color)
                                .frame(width: 24, alignment: .leading)
                            Text(player.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(store.tradedAway(from: team.abbrev).contains(player.name)
                                                 ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                                .strikethrough(store.tradedAway(from: team.abbrev).contains(player.name))
                            Spacer()
                            Text(player.aav.asCapMoney)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.vertical, 7)
                        if player.id != roster.last?.id {
                            Divider().overlay(Theme.Palette.border)
                        }
                    }
                }
            }
        }
    }
}
