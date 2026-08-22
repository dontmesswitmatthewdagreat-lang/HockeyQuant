import SwiftUI

/// Propose a pick trade to an AI GM.
///
/// The screen shows both sides' value as you build the offer, because the whole
/// lesson of trading up is how much the top of a round costs — hiding the number
/// would just make the AI look stubborn.
struct DraftTradeSheet: View {
    let engine: DraftRoomEngine
    var onTraded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var wanted: Set<DraftTrades.Asset> = []
    @State private var offered: Set<DraftTrades.Asset> = []
    @State private var result: DraftTrades.Verdict?

    /// Every open pick belonging to somebody else, nearest first.
    private var targets: [(overall: Int, team: String)] {
        engine.openPicks.filter { $0.team != engine.userTeam }
    }

    private var partner: String? {
        wanted.compactMap { asset -> String? in
            guard case .pick(let overall) = asset else { return nil }
            return engine.order[overall - 1]
        }.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    balance
                    wantSection
                    giveSection
                    if let result { verdictCard(result) }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundView().ignoresSafeArea())
            .navigationTitle("Trade picks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") { propose() }
                        .fontWeight(.bold)
                        .disabled(wanted.isEmpty || offered.isEmpty)
                }
            }
        }
    }

    // MARK: - Balance

    private var balance: some View {
        let get = DraftTrades.value(of: Array(wanted))
        let give = DraftTrades.value(of: Array(offered))
        return Card {
            VStack(spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    side("YOU GET", get, Theme.Palette.accent)
                    Text("for")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.top, 12)
                    side("YOU GIVE", give, Theme.Palette.textSecondary)
                }
                SplitBar(leftFraction: get + give > 0 ? get / (get + give) : 0.5,
                         leftColor: Theme.Palette.accent,
                         rightColor: Theme.Palette.textTertiary.opacity(0.5))
                Text(give >= get * DraftTrades.acceptanceMargin
                     ? "They should take this."
                     : "You're asking them to move down — that costs extra.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func side(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.6)
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(String(format: "%.0f", value))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text("value")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var wantSection: some View {
        SectionCard("What you want") {
            VStack(spacing: 6) {
                if targets.isEmpty {
                    Text("No other picks left to trade for.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                ForEach(targets, id: \.overall) { slot in
                    let asset = DraftTrades.Asset.pick(overall: slot.overall)
                    // One partner per deal: a three-way trade is a different
                    // feature, and silently splitting the offer would be worse.
                    let blocked = partner != nil && partner != slot.team
                    assetRow(asset, team: slot.team, selected: wanted.contains(asset),
                             disabled: blocked) {
                        toggle(asset, in: &wanted)
                    }
                }
            }
        }
    }

    private var giveSection: some View {
        SectionCard("What you give") {
            VStack(spacing: 6) {
                ForEach(engine.userAssets) { asset in
                    assetRow(asset, team: engine.userTeam, selected: offered.contains(asset),
                             disabled: false) {
                        toggle(asset, in: &offered)
                    }
                }
                if engine.userAssets.isEmpty {
                    Text("Nothing left to offer.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private func assetRow(_ asset: DraftTrades.Asset, team: String, selected: Bool,
                          disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: team, size: 24)
                Text(asset.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer(minLength: 0)
                Text(String(format: "%.0f", DraftTrades.value(of: asset)))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textTertiary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Theme.Palette.accent : Theme.Palette.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 8)
            .background(selected ? Theme.Palette.accent.opacity(0.10) : Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(selected ? Theme.Palette.accent : Theme.Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    private func verdictCard(_ verdict: DraftTrades.Verdict) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: verdict.accepted ? "checkmark.seal.fill" : "hand.raised.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(verdict.accepted ? Theme.Palette.positive : Theme.Palette.moderate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdict.accepted ? "Trade accepted" : "\(partner ?? "They") passed")
                        .font(Theme.Font.headlineHeavy())
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(verdict.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ asset: DraftTrades.Asset, in set: inout Set<DraftTrades.Asset>) {
        if set.contains(asset) { set.remove(asset) } else { set.insert(asset) }
        result = nil
    }

    private func propose() {
        guard let partner else { return }
        let verdict = DraftTrades.evaluate(giving: Array(offered), getting: Array(wanted))
        result = verdict
        guard verdict.accepted else {
            Haptics.tap()
            return
        }
        let ok = engine.applyTrade(with: partner,
                                   userGives: Array(offered),
                                   userGets: Array(wanted))
        guard ok else { return }
        Haptics.success()
        onTraded()
        dismiss()
    }
}
