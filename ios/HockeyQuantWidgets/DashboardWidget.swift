import WidgetKit
import SwiftUI

struct DashboardEntry: TimelineEntry {
    let date: Date
    let games: [LiveGame]
    let news: [String]
}

struct DashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry { DashboardEntry(date: .now, games: [], news: []) }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        Task {
            let e = await load()
            let refresh = e.games.contains(where: { $0.isLive }) ? 120.0 : 1800.0
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(refresh))))
        }
    }

    private func load() async -> DashboardEntry {
        let live = await WidgetFetcher.scoreboard().filter { $0.isLive }
        if live.isEmpty {
            return DashboardEntry(date: .now, games: [], news: await WidgetFetcher.topNews())
        }
        return DashboardEntry(date: .now, games: live, news: [])
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DashboardWidget", provider: DashboardProvider()) { entry in
            DashboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Live Games")
        .description("Live NHL scores — or the latest headlines when nothing's on.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DashboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardEntry

    private var maxRows: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.games.isEmpty {
                header("LIVE", systemImage: "dot.radiowaves.left.and.right", tint: Color(hex: 0xE5484D))
                ForEach(entry.games.prefix(maxRows)) { gameRow($0) }
                Spacer(minLength: 0)
            } else {
                header("AROUND THE LEAGUE", systemImage: "newspaper.fill", tint: Color(hex: 0x2563EB))
                if entry.news.isEmpty {
                    Text("No games live. Check back at puck drop.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(entry.news.prefix(maxRows).enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(Color(hex: 0x2563EB)).frame(width: 5, height: 5).padding(.top, 6)
                            Text(line).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(hex: 0xFFFFFF) }
    }

    private func header(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            Text(title).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
            Spacer()
        }
    }

    private func gameRow(_ g: LiveGame) -> some View {
        HStack(spacing: 8) {
            teamChip(g.away, g.awayScore, win: g.awayScore > g.homeScore)
            Text("–").foregroundStyle(.secondary)
            teamChip(g.home, g.homeScore, win: g.homeScore > g.awayScore)
            Spacer()
            Text(g.status).font(.system(size: 11, weight: .semibold)).foregroundStyle(g.isLive ? Color(hex: 0xE5484D) : .secondary)
        }
    }

    private func teamChip(_ team: String, _ score: Int, win: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(TeamInfo.lookup(team).color).frame(width: 8, height: 8)
            Text(team).font(.system(size: 13, weight: .bold))
            Text("\(score)").font(.system(size: 14, weight: .heavy, design: .rounded))
        }
    }
}
