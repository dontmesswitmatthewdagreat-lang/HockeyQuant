import SwiftUI

/// Flipboard-style News: header tabs (News / Prospects), an AI search bar, a
/// Play button (story walkthrough), and a magazine digest feed — key-point
/// bullets, a hero lead story, and image cards. Prospects = draft board + pool.
struct NewsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var store = NewsStore()
    @State private var tab = 0                 // 0 = News, 1 = Prospects
    @State private var prospectPage = 1        // 0 = Draft Board, 1 = My Team (default)
    @State private var showSearch = false
    @State private var showStory = false
    @AppStorage("watchedStoryDigestIds") private var watchedIds = ""
    @Namespace private var underlineNS

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    if tab == 0 { digestContent } else { prospectsContent }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.loadLatest(team: auth.favoriteTeam) }
        .task(id: tab) {
            // Load both prospect lists so swiping between them is instant.
            guard tab == 1 else { return }
            if let fav = auth.favoriteTeam, store.teamProspects.isEmpty {
                await store.loadTeamProspects(team: fav)
            }
            if store.draftProspects.isEmpty { await store.loadDraftProspects() }
        }
        .fullScreenCover(isPresented: $showStory) {
            NewsStoryView(digests: store.digests)
        }
        .sheet(isPresented: $showSearch) {
            NewsSearchView(store: store)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                segment("News", 0)
                segment("Prospects", 1)
                Spacer(minLength: Theme.Spacing.xs)
                AvatarButton()
            }
            if tab == 0 {
                Button { showSearch = true } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "magnifyingglass")
                        Text("Ask or search NHL news…")
                        Spacer()
                    }
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Palette.surface)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func segment(_ label: String, _ idx: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(tab == idx ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
            ZStack {
                if tab == idx {
                    Capsule().fill(Theme.Palette.accent).frame(height: 3)
                        .matchedGeometryEffect(id: "underline", in: underlineNS)
                } else {
                    Capsule().fill(.clear).frame(height: 3)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = idx } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == idx ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Digest

    @ViewBuilder
    private var digestContent: some View {
        if store.loading && store.digests.isEmpty {
            shimmer
        } else if store.digests.isEmpty {
            EmptyStateView(systemImage: "newspaper", title: "No digest yet",
                           message: "The morning roundup and your team's pre/post-game digests will appear here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    playCTA
                    ForEach(store.digests) { digest in
                        digestSection(digest)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await store.loadLatest(team: auth.favoriteTeam) }
        }
    }

    private var watchedCurrent: Bool {
        guard let id = store.digests.first?.id else { return false }
        return watchedIds.split(separator: ",").map(String.init).contains(id)
    }

    /// Headline photos used as the panning collage behind the play CTA.
    private var collageURLs: [URL] {
        Array(store.digests.flatMap { $0.items }.compactMap { $0.image }.prefix(10))
    }

    private var playCTA: some View {
        let count = store.digests.first?.items.count ?? 0
        let watched = watchedCurrent
        let urls = collageURLs
        let onPhoto = !watched && !urls.isEmpty   // text sits on the dark collage
        return Button { showStory = true } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    if watched {
                        Circle().fill(Theme.Palette.surface)
                            .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))
                    } else {
                        AnimatedTeamBackground(
                            colors: [Theme.Palette.accentAlt, Theme.Palette.accent, Theme.Palette.accentAlt],
                            base: Theme.Palette.accent,
                            radiusFactor: 0.8,
                            speed: 3.5
                        ).clipShape(Circle())
                    }
                    Image(systemName: watched ? "checkmark" : "play.fill")
                        .font(.system(size: 19, weight: .black))
                        .foregroundStyle(watched ? Theme.Palette.strong : .white)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(watched ? "You're caught up" : "Watch today's recap")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(onPhoto ? .white : Theme.Palette.textPrimary)
                        .shadow(color: onPhoto ? .black.opacity(0.5) : .clear, radius: 3, y: 1)
                    Text(watched ? "Tap to rewatch the stories"
                         : (count > 0 ? "\(count) top stories · tap to play" : "Tap to play"))
                        .font(Theme.Font.caption())
                        .foregroundStyle(onPhoto ? .white.opacity(0.9) : Theme.Palette.textSecondary)
                        .shadow(color: onPhoto ? .black.opacity(0.5) : .clear, radius: 2, y: 1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(onPhoto ? .white : (watched ? Theme.Palette.textTertiary : Theme.Palette.accent))
            }
            .padding(Theme.Spacing.md)
            .background {
                if onPhoto {
                    ZStack {
                        HeadlineCollage(urls: urls)
                        LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.45), .black.opacity(0.68)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                } else {
                    Theme.Palette.surface
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay {
                if watched {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .strokeBorder(Theme.Palette.border, lineWidth: 1)
                } else {
                    AnimatedGradientRing(cornerRadius: Theme.Radius.lg)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .animation(.easeOut(duration: 0.6), value: watched)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(watched ? "Rewatch news walkthrough" : "Play news walkthrough")
    }

    private func digestSection(_ d: NewsDigest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                if !d.isLeague { CrestView(abbrev: d.scope, size: 22) }
                Text(d.title).font(Theme.Font.title()).foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                kindBadge(d.kindLabel)
            }
            if let lead = d.items.first { heroCard(lead).staggeredEntrance(index: 0) }
            ForEach(Array(d.items.dropFirst().enumerated()), id: \.element.id) { i, item in
                compactCard(item).staggeredEntrance(index: min(i + 1, 8))
            }
        }
    }

    private func heroCard(_ item: DigestItem) -> some View {
        Button { open(item) } label: {
            ZStack(alignment: .bottomLeading) {
                newsImageFill(item, height: 240)
                LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    tagChip(item.tag)
                    Text(item.headline).font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white).multilineTextAlignment(.leading)
                    Text(item.source).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(Theme.Spacing.md)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func compactCard(_ item: DigestItem) -> some View {
        Button { open(item) } label: {
            ZStack(alignment: .bottomLeading) {
                newsImageFill(item, height: 196)
                LinearGradient(colors: [.clear, .black.opacity(0.2), .black.opacity(0.88)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        tagChip(item.tag)
                        Text(item.source).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    Text(item.headline).font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white).multilineTextAlignment(.leading).lineLimit(2)
                    Text(item.blurb).font(Theme.Font.caption())
                        .foregroundStyle(.white.opacity(0.82)).lineLimit(2)
                }
                .padding(Theme.Spacing.md)
            }
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// A photo filling a definite width×height box, center-cropped (so the image
    /// stays centered instead of overflowing off the right edge).
    private func newsImageFill(_ item: DigestItem, height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { newsImage(item) }
            .clipped()
    }

    @ViewBuilder
    private func newsImage(_ item: DigestItem) -> some View {
        if let url = item.image {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { placeholderFill(item.tag) }
            }
        } else {
            placeholderFill(item.tag)
        }
    }

    private func placeholderFill(_ tag: String) -> some View {
        let c = tagColor(tag)
        return LinearGradient(colors: [c.opacity(0.55), c.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "hockey.puck.fill").font(.system(size: 26)).foregroundStyle(.white.opacity(0.55)))
    }

    private func open(_ item: DigestItem) {
        if let url = URL(string: item.url) { openURL(url) }
    }

    // MARK: - Prospects

    @ViewBuilder
    private var prospectsContent: some View {
        if let fav = auth.favoriteTeam {
            VStack(spacing: 0) {
                prospectIndicator
                TabView(selection: $prospectPage) {
                    prospectGrid(store.draftProspects, loading: store.loadingDraft, draftBoard: true) {
                        await store.loadDraftProspects()
                    }.tag(0)
                    prospectGrid(store.teamProspects, loading: store.loadingTeam, draftBoard: false) {
                        await store.loadTeamProspects(team: fav)
                    }.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: prospectPage)
            }
        } else {
            prospectGrid(store.draftProspects, loading: store.loadingDraft, draftBoard: true) {
                await store.loadDraftProspects()
            }
        }
    }

    /// Passive Draft Board / My Team indicator — a chip + page dots, deliberately
    /// distinct from the underline-style News/Prospects tab buttons so it reads as
    /// "swipe between these," not "tap these."
    private var prospectIndicator: some View {
        VStack(spacing: 7) {
            HStack(spacing: Theme.Spacing.sm) {
                prospectChip("Draft Board", 0)
                prospectChip("My Team", 1)
            }
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule()
                        .fill(prospectPage == i ? Theme.Palette.accent : Theme.Palette.border)
                        .frame(width: prospectPage == i ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxs)
        .padding(.bottom, Theme.Spacing.sm)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: prospectPage)
    }

    private func prospectChip(_ label: String, _ idx: Int) -> some View {
        let active = prospectPage == idx
        return Text(label)
            .font(.system(size: 13, weight: active ? .bold : .medium, design: .rounded))
            .foregroundStyle(active ? .white : Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .background { if active { Capsule().fill(Theme.Palette.accent) } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(active ? "selected" : "swipe to view")
    }

    @ViewBuilder
    private func prospectGrid(_ items: [Prospect], loading: Bool, draftBoard: Bool,
                              refresh: @escaping () async -> Void) -> some View {
        if loading && items.isEmpty {
            shimmer
        } else if items.isEmpty {
            EmptyStateView(systemImage: "figure.hockey", title: "No prospects",
                           message: draftBoard ? "The draft board will appear here."
                                               : "No tracked prospects for this team yet.")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm),
                                    GridItem(.flexible(), spacing: Theme.Spacing.sm)],
                          spacing: Theme.Spacing.sm) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                        prospectCard(p, rank: i + 1).staggeredEntrance(index: min(i, 10))
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await refresh() }
        }
    }

    private func prospectCard(_ p: Prospect, rank: Int) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack(alignment: .topLeading) {
                // Headshot (team prospects) or initials monogram (draft board —
                // the NHL has no photos for undrafted players).
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.Palette.accent.opacity(0.55), Theme.Palette.accentAlt.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let url = p.headshotURL {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                monogram(p)
                            }
                        }
                    } else {
                        monogram(p)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))
                .frame(maxWidth: .infinity)

                // Rank (draft board) or team crest (my team).
                if p.team == nil {
                    Text("\(p.ranking ?? rank)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Theme.Palette.accent).clipShape(Circle())
                } else {
                    CrestView(abbrev: p.team ?? "", size: 26)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let flag = p.flag { Text(flag).font(.system(size: 13)) }
                Text(p.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Text(p.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if p.team != nil, let r = p.ranking {
                Text("#\(r) prospect")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.accent)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .top)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            .strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    private func monogram(_ p: Prospect) -> some View {
        Text(p.initials)
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
    }

    // MARK: - Shared

    private var shimmer: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.sm) {
                LoadingShimmer(height: 200)
                ForEach(0..<4, id: \.self) { _ in LoadingShimmer(height: 88) }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private func kindBadge(_ label: String) -> some View {
        let color: Color = switch label {
        case "Morning": Theme.Palette.accent
        case "Evening": Theme.Palette.accentAlt
        case "Pre-Game": Theme.Palette.moderate
        default: Theme.Palette.strong
        }
        return Text(label.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3).background(color.opacity(0.14)).clipShape(Capsule())
    }

    private func tagChip(_ tag: String) -> some View {
        Text(tag.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2).background(tagColor(tag)).clipShape(Capsule())
    }

    private func tagColor(_ tag: String) -> Color {
        switch tag {
        case "Injury": return Theme.Palette.negative
        case "Rumor", "Lineup": return Theme.Palette.moderate
        case "Recap", "Game": return Theme.Palette.strong
        case "Analysis": return Theme.Palette.accentAlt
        default: return Theme.Palette.accent
        }
    }
}
