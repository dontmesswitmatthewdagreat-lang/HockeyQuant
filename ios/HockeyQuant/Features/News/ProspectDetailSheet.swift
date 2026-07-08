import SwiftUI
import Charts

/// Tap-through detail for a prospect: bio hero, current mock-draft projection,
/// Central Scouting ranking trend, and their latest news (with the Premium
/// hold-to-summarize the news feed already has).
struct ProspectDetailSheet: View {
    let prospect: Prospect
    @Environment(PremiumStore.self) private var premium
    @Environment(\.openURL) private var openURL
    @State private var detail: ProspectDetailResponse?
    @State private var failed = false
    @State private var summaryItem: DigestItem?
    @State private var showPaywall = false
    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    hero
                    if let drafted = detail?.drafted {
                        draftedCard(drafted)
                    } else if let proj = detail?.projection {
                        projectionCard(proj)
                    }
                    if let history = detail?.rankHistory, history.count >= 2 { trendCard(history) }
                    newsCard
                }
                .padding(Theme.Spacing.md)
                .padding(.top, Theme.Spacing.lg)
            }
        }
        .task {
            guard let nhlId = prospect.nhlId else { failed = true; return }
            do { detail = try await api.prospectDetail(nhlId: nhlId) }
            catch { failed = true }
        }
        .sheet(item: $summaryItem) { item in
            NewsSummarySheet(item: item)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [Theme.Palette.accent.opacity(0.55), Theme.Palette.accentAlt.opacity(0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                if let url = prospect.headshotURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { monogram }
                    }
                } else { monogram }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

            HStack(spacing: 6) {
                if let flag = prospect.flag { Text(flag).font(.system(size: 20)) }
                Text(prospect.name)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            Text(bioLine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.xs) {
                if let rank = prospect.ranking {
                    StatusPill(text: "#\(rank) \(shortCategory)", color: Theme.Palette.accent, solid: true)
                }
                if let delta = prospect.rankDelta, delta != 0 {
                    StatusPill(text: "\(delta > 0 ? "▲" : "▼") \(abs(delta))",
                               color: delta > 0 ? Theme.Palette.positive : Theme.Palette.negative)
                }
                if let team = prospect.team, !team.isEmpty {
                    StatusPill(text: team, color: TeamInfo.lookup(team).color)
                }
            }
        }
    }

    private var monogram: some View {
        Text(prospect.initials)
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
    }

    private var bioLine: String {
        var parts: [String] = []
        if let p = prospect.position { parts.append(p) }
        if let club = prospect.info?.club, !club.isEmpty { parts.append(club) }
        else if let league = prospect.league, !league.isEmpty { parts.append(league) }
        if let year = prospect.draftYear { parts.append("\(year) draft") }
        return parts.joined(separator: " · ")
    }

    private var shortCategory: String {
        switch prospect.info?.category {
        case "north-american-skater": return "NA skater"
        case "international-skater":   return "Intl skater"
        case "north-american-goalie": return "NA goalie"
        case "international-goalie":   return "Intl goalie"
        default:                      return "ranked"
        }
    }

    // MARK: - Actual draft result (post-draft)

    private func draftedCard(_ pick: DraftedPick) -> some View {
        let teamColor = pick.team.map { TeamInfo.lookup($0).color } ?? Theme.Palette.accent
        return SectionCard("Drafted") {
            HStack(spacing: Theme.Spacing.sm) {
                if let team = pick.team { CrestView(abbrev: team, size: 44) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("#\(pick.overall) overall · \(pick.team ?? "?")")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(draftedLine(pick))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                StatusPill(text: "OFFICIAL", color: teamColor, solid: true)
            }
        }
    }

    private func draftedLine(_ pick: DraftedPick) -> String {
        var parts: [String] = []
        if let round = pick.round { parts.append("Round \(round)") }
        if let year = prospect.draftYear { parts.append("\(year) NHL Draft") }
        if let club = pick.club, !club.isEmpty { parts.append("from \(club)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Projection

    private func projectionCard(_ proj: ProspectProjection) -> some View {
        SectionCard("Mock draft projection") {
            HStack(spacing: Theme.Spacing.sm) {
                if let team = proj.team { CrestView(abbrev: team, size: 44) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(projLine(proj))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let reason = proj.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let edition = proj.edition {
                        Text("Edition \(edition)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func projLine(_ proj: ProspectProjection) -> String {
        if let overall = proj.overall, let team = proj.team {
            return "#\(overall) overall to \(team)"
        }
        return "Projected first-rounder"
    }

    // MARK: - Ranking trend

    private func trendCard(_ history: [RankPoint]) -> some View {
        SectionCard("Ranking trend") {
            Chart(history) { point in
                LineMark(x: .value("List", point.listDate), y: .value("Rank", point.rank))
                    .foregroundStyle(Theme.Palette.accent)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("List", point.listDate), y: .value("Rank", point.rank))
                    .foregroundStyle(Theme.Palette.accent)
            }
            // Rank 1 belongs at the top.
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartXAxis(.hidden)
            .frame(height: 110)
            Text("Central Scouting rank across lists — up is better.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // MARK: - News

    private var newsCard: some View {
        SectionCard("Latest news") {
            if let news = detail?.news, !news.isEmpty {
                VStack(spacing: 0) {
                    ForEach(news) { item in
                        newsRow(item)
                        if item.id != news.last?.id {
                            Divider().overlay(Theme.Palette.border)
                        }
                    }
                }
                Text("Tap to open · hold for an AI summary")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else if failed || detail != nil {
                Text("No recent stories found.")
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.textTertiary)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 34) }
                }
            }
        }
    }

    private func newsRow(_ item: ProspectNewsItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.accent)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let source = item.source {
                    Text(source)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if let u = URL(string: item.url) { openURL(u) } }
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 30) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if premium.isPremium {
                summaryItem = DigestItem(headline: item.headline, blurb: item.blurb ?? "",
                                         tag: "PROSPECT", source: item.source ?? "News",
                                         url: item.url, publishedAt: item.publishedAt, imageUrl: nil)
            } else {
                showPaywall = true
            }
        }
    }
}
