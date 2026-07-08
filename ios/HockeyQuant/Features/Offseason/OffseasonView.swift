import SwiftUI

/// Offseason GM playground (Premium): real FA pool + real cap sheets. Sign
/// free agents, build trades, and share the moves timeline as an image.
struct OffseasonView: View {
    @Environment(PremiumStore.self) private var premium
    @State private var store = OffseasonStore()
    @State private var segment = 0
    @State private var showPaywall = false

    // Market segment state
    @State private var search = ""
    @State private var positionFilter = "All"

    // Sheets
    @State private var signingAgent: FreeAgent?
    @State private var capTeam: TeamCapInfo?
    @State private var showTradeBuilder = false

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if premium.isPremium {
                content
            } else {
                lockedPreview
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.load() }
        .sheet(item: $signingAgent) { agent in
            SignPlayerSheet(store: store, agent: agent)
                .presentationDetents([.large])
        }
        .sheet(item: $capTeam) { team in
            TeamCapSheet(store: store, team: team, onTrade: {
                capTeam = nil
                showTradeBuilder = true
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTradeBuilder) {
            TradeBuilderView(store: store)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Premium gate

    private var lockedPreview: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroBand
                VStack(spacing: Theme.Spacing.md) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text("A Premium playground")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("Sign this summer's real free agents, make trades against every team's real cap space, and share your moves timeline anywhere.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                    Button { showPaywall = true } label: {
                        CapsuleActionLabel(title: "Unlock with Premium", systemImage: "crown.fill", prominent: true)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroBand
                VStack(spacing: Theme.Spacing.md) {
                    BigSegment(selection: $segment, options: ["Market", "Teams", "Moves"])
                    ZStack {
                        switch segment {
                        case 0: marketSegment.transition(.opacity)
                        case 1: teamsSegment.transition(.opacity)
                        default: movesSegment.transition(.opacity)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: segment)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .refreshable { await store.load() }
    }

    private var heroBand: some View {
        HeroBand(tint: Color(hex: 0xFF9500)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    BackChip()
                    Spacer()
                    BandPill(text: "\(store.moves.count) moves", systemImage: "list.bullet")
                }
                Text("Offseason GM")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(marketSubtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var marketSubtitle: String {
        if let m = store.market {
            return "\(m.freeAgents.count) free agents · \(m.capCeiling.asCapMoney) cap ceiling · real data"
        }
        return "Real free agents · real cap space"
    }

    // MARK: - Market (free agents)

    private let positionOptions = ["All", "C", "W", "D", "G"]

    private var filteredAgents: [FreeAgent] {
        guard let m = store.market else { return [] }
        let signed = store.signedAgents
        return m.freeAgents.filter { agent in
            if signed[agent.name] != nil { return false }
            switch positionFilter {
            case "C": if agent.position != "C" { return false }
            case "W": if !["LW", "RW", "W", "F"].contains(agent.position) { return false }
            case "D": if agent.position != "D" { return false }
            case "G": if agent.position != "G" { return false }
            default: break
            }
            if !search.isEmpty && !agent.name.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
    }

    @ViewBuilder
    private var marketSegment: some View {
        switch store.state {
        case .idle, .loading:
            VStack(spacing: Theme.Spacing.md) {
                ForEach(0..<6, id: \.self) { _ in LoadingShimmer(height: 64) }
            }
        case .error(let message):
            ErrorStateView(message: message) { Task { await store.load() } }
        case .loaded:
            VStack(spacing: Theme.Spacing.sm) {
                searchField
                filterChips
                ForEach(filteredAgents.prefix(80)) { agent in
                    agentRow(agent)
                }
                if filteredAgents.isEmpty {
                    Text("No free agents match.")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.vertical, Theme.Spacing.lg)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField("Search free agents", text: $search)
                .font(.system(size: 15))
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 11)
        .background(Theme.Palette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    private var filterChips: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(positionOptions, id: \.self) { opt in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { positionFilter = opt }
                } label: {
                    Text(opt)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(positionFilter == opt ? .white : Theme.Palette.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(positionFilter == opt ? AnyShapeStyle(Theme.Palette.accent)
                                                          : AnyShapeStyle(Theme.Palette.border.opacity(0.45)))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func agentRow(_ agent: FreeAgent) -> some View {
        PressableButton(action: { signingAgent = agent }) {
            HStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: agent.prevTeam ?? "?", size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                    Text(agentSubtitle(agent))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let aav = agent.prevAav {
                        Text(aav.asCapMoney)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    StatusPill(text: agent.type,
                               color: agent.type == "UFA" ? Theme.Palette.accent : Theme.Palette.moderate)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1))
        }
    }

    private func agentSubtitle(_ agent: FreeAgent) -> String {
        var parts = [agent.position]
        if let age = agent.age { parts.append("\(age) yrs") }
        if let prev = agent.prevTeam { parts.append("last: \(prev)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Teams (cap sheets)

    @ViewBuilder
    private var teamsSegment: some View {
        if let m = store.market {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(m.teams.sorted { store.effectiveSpace(for: $0.abbrev) ?? 0 > store.effectiveSpace(for: $1.abbrev) ?? 0 }) { team in
                    teamRow(team, ceiling: m.capCeiling)
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(0..<6, id: \.self) { _ in LoadingShimmer(height: 64) }
            }
        }
    }

    private func teamRow(_ team: TeamCapInfo, ceiling: Double) -> some View {
        let space = store.effectiveSpace(for: team.abbrev) ?? team.capSpace
        let hit = store.effectiveHit(for: team.abbrev) ?? team.capHit
        return PressableButton(action: { capTeam = team }) {
            HStack(spacing: Theme.Spacing.sm) {
                CrestView(abbrev: team.abbrev, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(TeamInfo.lookup(team.abbrev).name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(space.asCapMoney)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(space < 0 ? Theme.Palette.negative : Theme.Palette.positive)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Palette.border.opacity(0.5))
                            Capsule()
                                .fill(hit > ceiling ? Theme.Palette.negative : TeamInfo.lookup(team.abbrev).color)
                                .frame(width: geo.size.width * min(hit / ceiling, 1))
                        }
                    }
                    .frame(height: 6)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1))
        }
    }

    // MARK: - Moves (timeline)

    @ViewBuilder
    private var movesSegment: some View {
        if store.moves.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text("No moves yet")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Sign a free agent or build a trade — every move lands on this timeline, ready to screenshot or share.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { segment = 0 }
                } label: {
                    CapsuleActionLabel(title: "Browse free agents", systemImage: "person.badge.plus", prominent: true)
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.vertical, Theme.Spacing.xl)
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                OffseasonTimelineList(store: store)
                shareButton
                Button(role: .destructive) {
                    withAnimation { store.clearMoves() }
                } label: {
                    Text("Clear all moves")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.negative)
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let image = renderShareCard() {
            ShareLink(
                item: image,
                preview: SharePreview("My NHL offseason", image: image)
            ) {
                CapsuleActionLabel(title: "Share timeline", systemImage: "square.and.arrow.up", prominent: true)
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func renderShareCard() -> Image? {
        let renderer = ImageRenderer(content: OffseasonShareCard(moves: store.moves, store: store))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

/// Timeline rows with a vertical connector, numbered pucks, and swipe-free
/// inline delete.
struct OffseasonTimelineList: View {
    var store: OffseasonStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.moves.enumerated()), id: \.element.id) { i, move in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle().fill(move.kind == .signing ? Theme.Palette.accent : Color(hex: 0xFF9500))
                            Text("\(i + 1)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 26, height: 26)
                        if i < store.moves.count - 1 {
                            Rectangle().fill(Theme.Palette.border).frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    MoveCard(move: move) { store.removeMove(move.id) }
                        .padding(.bottom, Theme.Spacing.sm)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct MoveCard: View {
    let move: GMMove
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: move.kind == .signing ? "signature" : "arrow.triangle.swap")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(move.kind == .signing ? Theme.Palette.accent : Color(hex: 0xFF9500))
                Text(move.kind == .signing ? "SIGNING" : "TRADE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            if move.kind == .signing {
                Text(move.headline)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                tradeDetail
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            .strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    private var tradeDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            tradeLine(from: move.teamA, to: move.teamB, pieces: move.piecesAtoB ?? [])
            tradeLine(from: move.teamB, to: move.teamA, pieces: move.piecesBtoA ?? [])
        }
    }

    private func tradeLine(from: String?, to: String?, pieces: [TradePiece]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(from ?? "?") → \(to ?? "?")")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(pieces.isEmpty ? "—" : pieces.map(\.name).joined(separator: ", "))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Small "‹ back" chip for band headers on pushed screens.
struct BackChip: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
