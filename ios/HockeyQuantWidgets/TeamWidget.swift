import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Team picker (config)

struct TeamEntity: AppEntity {
    let id: String      // abbrev
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = TeamQuery()
}

struct TeamQuery: EntityQuery {
    private func all() -> [TeamEntity] {
        TeamInfo.all.values.map { TeamEntity(id: $0.abbrev, name: $0.name) }.sorted { $0.name < $1.name }
    }
    func entities(for ids: [String]) async throws -> [TeamEntity] {
        let map = Dictionary(uniqueKeysWithValues: all().map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }
    func suggestedEntities() async throws -> [TeamEntity] { all() }
    func defaultResult() async -> TeamEntity? { all().first { $0.id == "CAR" } ?? all().first }
}

struct TeamConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Team"
    static var description = IntentDescription("Pick the team to follow.")
    @Parameter(title: "Team") var team: TeamEntity?
}

// MARK: - Timeline

struct TeamEntry: TimelineEntry {
    let date: Date
    let abbrev: String
    let name: String
    let game: LiveGame?
}

struct TeamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamEntry {
        TeamEntry(date: .now, abbrev: "CAR", name: "Carolina", game: nil)
    }
    func snapshot(for configuration: TeamConfigIntent, in context: Context) async -> TeamEntry {
        await entry(configuration)
    }
    func timeline(for configuration: TeamConfigIntent, in context: Context) async -> Timeline<TeamEntry> {
        let e = await entry(configuration)
        let refresh = (e.game?.isLive == true) ? 120.0 : 1800.0
        return Timeline(entries: [e], policy: .after(Date().addingTimeInterval(refresh)))
    }
    private func entry(_ config: TeamConfigIntent) async -> TeamEntry {
        let abbrev = config.team?.id ?? "CAR"
        let name = config.team?.name ?? "Carolina"
        return TeamEntry(date: .now, abbrev: abbrev, name: name, game: await WidgetFetcher.teamGame(abbrev))
    }
}

// MARK: - Widget

struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TeamWidget", intent: TeamConfigIntent.self, provider: TeamProvider()) { entry in
            TeamWidgetView(entry: entry)
        }
        .configurationDisplayName("My Team")
        .description("Your team's live score or next game.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct TeamWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TeamEntry

    private var color: Color { TeamInfo.lookup(entry.abbrev).color }

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // Home-screen small — diagonal split of the two teams' colors (a matchup).
    private var small: some View {
        Group {
            if let g = entry.game { matchup(g) } else { noGame }
        }
        .containerBackground(for: .widget) {
            if let g = entry.game {
                DiagonalSplit(away: TeamInfo.lookup(g.away).color, home: TeamInfo.lookup(g.home).color)
            } else {
                LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private func matchup(_ g: LiveGame) -> some View {
        let showScore = g.isLive || g.isFinal
        return ZStack {
            // Away — top-left, on its color triangle.
            VStack { HStack { side(g.away, g.awayScore, showScore, trailing: false); Spacer() }; Spacer() }
            // Home — bottom-right, on its color triangle.
            VStack { Spacer(); HStack { Spacer(); side(g.home, g.homeScore, showScore, trailing: true) } }
            // Status — centered over the diagonal.
            Text(g.status.isEmpty ? "vs" : g.status)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.4), in: Capsule())
        }
        .padding(12)
    }

    private func side(_ team: String, _ score: Int, _ showScore: Bool, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: -2) {
            Text(team).font(.system(size: 19, weight: .heavy, design: .rounded))
            if showScore { Text("\(score)").font(.system(size: 28, weight: .black, design: .rounded)) }
        }
        .foregroundStyle(Self.contrast(TeamInfo.lookup(team).colorHex))
    }

    private var noGame: some View {
        VStack(spacing: 4) {
            Text(entry.abbrev).font(.system(size: 18, weight: .heavy, design: .rounded))
            Text("No upcoming game").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
    }

    // Lock-screen accessory
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let g = entry.game {
                if g.isLive || g.isFinal {
                    Text("\(g.away) \(g.awayScore)–\(g.homeScore) \(g.home)").font(.system(size: 14, weight: .semibold))
                } else {
                    Text("\(g.away) @ \(g.home)").font(.system(size: 14, weight: .semibold))
                }
                Text(g.status).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text("\(entry.abbrev): no upcoming game").font(.system(size: 13))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    /// Black or white text depending on the team color's luminance (for readable
    /// text on light colors like gold).
    static func contrast(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.62 ? .black : .white
    }
}

/// Two-color diagonal split (away top-left, home bottom-right) with a divider.
struct DiagonalSplit: View {
    let away: Color
    let home: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                away
                Path { p in
                    p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                }
                .fill(home)
                Path { p in p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: 0, y: h)) }
                    .stroke(.white.opacity(0.55), lineWidth: 1.5)
            }
        }
    }
}
