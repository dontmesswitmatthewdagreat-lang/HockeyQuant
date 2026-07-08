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
    @State private var prospectQuery = ""      // live filter for the prospect lists
    @State private var showSearch = false
    @State private var showStory = false
    @Environment(PremiumStore.self) private var premium
    @State private var summaryItem: DigestItem?
    @State private var showPaywall = false
    @State private var detailProspect: Prospect?
    @State private var mockSource: String?     // selected insider mock (nil = first)
    @AppStorage("watchedStoryDigestIds") private var watchedIds = ""
    @AppStorage("seenMockEdition") private var seenMockEdition = ""
    @Namespace private var underlineNS

    /// A fresh weekly mock draft the user hasn't opened yet (drives the badge + reveal).
    private var isNewMock: Bool {
        guard let ed = store.mockDraft?.edition, !ed.isEmpty else { return false }
        return ed != seenMockEdition
    }

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
        .task(id: auth.favoriteTeam) {
            await store.loadLatest(team: auth.favoriteTeam)
            // Load the mock draft up front so the "new" badge can pull the user
            // into Prospects even while they're still on the News tab.
            if store.mockDraft == nil { await store.loadMockDraft() }
        }
        .task(id: tab) {
            // Load every prospect list so swiping between them is instant.
            guard tab == 1 else { return }
            if let fav = auth.favoriteTeam {
                if store.teamProspects.isEmpty { await store.loadTeamProspects(team: fav) }
                if store.draftClass.isEmpty { await store.loadDraftClass(team: fav) }
            }
            if store.draftProspects.isEmpty { await store.loadDraftProspects() }
        }
        .fullScreenCover(isPresented: $showStory) {
            NewsStoryView(digests: store.digests)
        }
        .sheet(isPresented: $showSearch) {
            NewsSearchView(store: store)
        }
        .sheet(item: $summaryItem) { item in
            NewsSummarySheet(item: item)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $detailProspect) { prospect in
            ProspectDetailSheet(prospect: prospect)
                .presentationDetents([.large])
        }
    }

    /// Long-press on any news card → AI summary (Premium) or the paywall.
    private func requestSummary(_ item: DigestItem) {
        if premium.isPremium { summaryItem = item } else { showPaywall = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                segment("News", 0)
                segment("Prospects", 1, badge: isNewMock)
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

    private func segment(_ label: String, _ idx: Int, badge: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(tab == idx ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Theme.Palette.defaultAccentAlt)
                            .frame(width: 8, height: 8)
                            .offset(x: 10, y: -1)
                    }
                }
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
                    ForEach(orderedDigests) { digest in
                        digestSection(digest)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await store.loadLatest(team: auth.favoriteTeam) }
        }
    }

    /// Feed order: the favorite team's digests lead, league news follows.
    private var orderedDigests: [NewsDigest] {
        store.digests.filter { !$0.isLeague } + store.digests.filter(\.isLeague)
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
            let items = orderedItems(d)
            if let lead = items.first { heroCard(lead).staggeredEntrance(index: 0) }
            ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { i, item in
                compactCard(item).staggeredEntrance(index: min(i + 1, 8))
            }
        }
    }

    /// League digests float stories about the favorite team to the top
    /// (matched on team name/nickname in the headline or blurb).
    private func orderedItems(_ d: NewsDigest) -> [DigestItem] {
        guard d.isLeague, let fav = auth.favoriteTeam else { return d.items }
        let info = TeamInfo.lookup(fav)
        let needles = [info.name.lowercased(),
                       info.name.components(separatedBy: " ").last?.lowercased() ?? ""]
            .filter { $0.count > 3 }
        func isFav(_ it: DigestItem) -> Bool {
            let text = "\(it.headline) \(it.blurb)".lowercased()
            return needles.contains { text.contains($0) }
        }
        return d.items.filter(isFav) + d.items.filter { !isFav($0) }
    }

    private func heroCard(_ item: DigestItem) -> some View {
        Group {
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
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .onTapGesture { open(item) }
        .modifier(HoldToSummarize { requestSummary(item) })
        .accessibilityAddTraits(.isButton)
    }

    private func compactCard(_ item: DigestItem) -> some View {
        Group {
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
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .onTapGesture { open(item) }
        .modifier(HoldToSummarize { requestSummary(item) })
        .accessibilityAddTraits(.isButton)
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
                prospectSearchBar
                prospectIndicator
                TabView(selection: $prospectPage) {
                    prospectGrid(store.draftProspects, loading: store.loadingDraft, draftBoard: true) {
                        await store.loadDraftProspects()
                    }.tag(0)
                    prospectGrid(store.teamProspects, loading: store.loadingTeam, draftBoard: false) {
                        await store.loadTeamProspects(team: fav)
                    }.tag(1)
                    mockDraftPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: prospectPage)
            }
        } else {
            VStack(spacing: 0) {
                prospectSearchBar
                prospectGrid(store.draftProspects, loading: store.loadingDraft, draftBoard: true) {
                    await store.loadDraftProspects()
                }
            }
        }
    }

    private var prospectSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField("Search prospects", text: $prospectQuery)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !prospectQuery.isEmpty {
                Button {
                    prospectQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 9)
        .background(Theme.Palette.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// Case-insensitive filter over name / league / position.
    private func filtered(_ items: [Prospect]) -> [Prospect] {
        let q = prospectQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.name.lowercased().contains(q)
                || ($0.league?.lowercased().contains(q) ?? false)
                || ($0.position?.lowercased().contains(q) ?? false)
        }
    }

    /// Draft prospects grouped into the NHL's four Central Scouting lists, in order.
    private func draftGroups(_ items: [Prospect]) -> [(key: String, title: String, items: [Prospect])] {
        Dictionary(grouping: items) { $0.info?.category ?? "other" }
            .map { (key: $0.key, title: $0.value.first?.categoryLabel ?? "Other", items: $0.value) }
            .sorted { ($0.items.first?.categoryOrder ?? 9) < ($1.items.first?.categoryOrder ?? 9) }
    }

    /// The same big pill switcher the rest of the app uses; swiping the pages
    /// underneath still works and stays in sync.
    private var prospectIndicator: some View {
        BigSegment(selection: $prospectPage, options: ["Draft Board", "My Team", "Mock Draft"])
            .overlay(alignment: .topTrailing) {
                if isNewMock && prospectPage != 2 {
                    Circle().fill(Theme.Palette.defaultAccentAlt)
                        .frame(width: 8, height: 8)
                        .offset(x: -10, y: 6)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
    }

    @ViewBuilder
    private func prospectGrid(_ allItems: [Prospect], loading: Bool, draftBoard: Bool,
                              refresh: @escaping () async -> Void) -> some View {
        let items = filtered(allItems)
        if loading && allItems.isEmpty {
            shimmer
        } else if allItems.isEmpty {
            EmptyStateView(systemImage: "figure.hockey", title: "No prospects",
                           message: draftBoard ? "The draft board will appear here."
                                               : "No tracked prospects for this team yet.")
        } else if items.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass", title: "No matches",
                           message: "No prospects match “\(prospectQuery)”.")
        } else {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    if draftBoard {
                        if prospectQuery.isEmpty { podiumHero(items) }
                        // The NHL ranks four separate lists; group + label them so
                        // the per-list "#1, #2, …" numbering reads correctly.
                        ForEach(draftGroups(items), id: \.key) { group in
                            Section {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { i, p in
                                    prospectRow(p, rank: p.ranking ?? (i + 1)).staggeredEntrance(index: min(i, 10))
                                }
                            } header: {
                                prospectSectionHeader(group.title, count: group.items.count)
                            }
                        }
                    } else {
                        if !store.draftClass.isEmpty {
                            draftClassSection
                        }
                        prospectSectionHeader("Prospect pool", count: items.count)
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                            prospectRow(p, rank: p.ranking ?? (i + 1)).staggeredEntrance(index: min(i, 10))
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await refresh() }
        }
    }

    // MARK: - Podium hero (draft board top 3)

    /// The top three of the first Central Scouting list on a gradient stage —
    /// silver / gold / bronze, gold elevated in the middle.
    @ViewBuilder
    private func podiumHero(_ items: [Prospect]) -> some View {
        let top = Array((draftGroups(items).first?.items.prefix(3)) ?? [])
        if top.count == 3 {
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                podiumColumn(top[1], rank: 2, size: 58)
                podiumColumn(top[0], rank: 1, size: 74).offset(y: -12)
                podiumColumn(top[2], rank: 3, size: 58)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.lg + 12)
            .padding(.bottom, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .padding(.bottom, Theme.Spacing.xs)
        }
    }

    private func podiumColumn(_ p: Prospect, rank: Int, size: CGFloat) -> some View {
        PressableButton(action: { detailProspect = p }) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    ZStack {
                        Circle().fill(.white.opacity(0.25))
                        if let url = p.headshotURL {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() } else { monogram(p) }
                            }
                        } else { monogram(p) }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(medallionColor(rank), lineWidth: 3))
                    Text("\(rank)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(medallionColor(rank)))
                        .offset(y: 8)
                }
                .padding(.bottom, 6)
                Text(p.name.components(separatedBy: " ").last ?? p.name)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(p.position ?? "")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actual draft class (My Team, post-draft)

    private var draftClassSection: some View {
        VStack(spacing: Theme.Spacing.xs) {
            prospectSectionHeader("This year's draft class", count: store.draftClass.count)
            ForEach(store.draftClass) { pick in
                HStack(spacing: Theme.Spacing.sm) {
                    VStack(spacing: 0) {
                        Text("R\(pick.round ?? 0)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("\(pick.overall)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                                     startPoint: .top, endPoint: .bottom))
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.player)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                        Text([pick.position, pick.club ?? pick.league].compactMap(\.self).joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    StatusPill(text: "DRAFTED", color: Theme.Palette.positive)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Theme.Palette.accent.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    private func prospectSectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xxs)
    }

    // MARK: - Mock draft (3rd Prospects page)

    private var selectedMock: MockDraft? {
        if let mockSource, let m = store.mocks.first(where: { $0.sourceLabel == mockSource }) { return m }
        return store.mockDraft ?? store.mocks.first
    }

    @ViewBuilder
    private var mockDraftPage: some View {
        if store.loadingMock && store.mocks.isEmpty && store.mockDraft == nil {
            shimmer
        } else if let mock = selectedMock, !mock.picks.isEmpty {
            VStack(spacing: 0) {
                if store.mocks.count > 1 { mockSourcePicker }
                MockDraftBoard(
                    mock: mock,
                    reveal: mock.isInternal && isNewMock && prospectPage == 2,
                    onRevealComplete: { seenMockEdition = mock.edition }
                )
                .id(mock.id)
            }
        } else {
            EmptyStateView(systemImage: "list.number", title: "No mock draft yet",
                           message: "This week's projected first round will appear here.")
        }
    }

    /// Switch between the internal projection and imported insider mocks.
    private var mockSourcePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(store.mocks) { mock in
                    let active = selectedMock?.id == mock.id
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            mockSource = mock.sourceLabel
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mock.isInternal ? "cpu" : "person.text.rectangle")
                                .font(.system(size: 10, weight: .bold))
                            Text(mock.isInternal ? "HockeyQuant" : mock.sourceLabel)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(active ? .white : Theme.Palette.textSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(active ? AnyShapeStyle(LinearGradient(
                            colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                            startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Theme.Palette.border.opacity(0.45)))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.bottom, Theme.Spacing.sm)
    }

    /// The projected first round, with a one-time slot-machine reveal for a new edition.
    private struct MockDraftBoard: View {
        let mock: MockDraft
        let reveal: Bool
        let onRevealComplete: () -> Void
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var start = Date()
        @State private var finished = false

        private let spin = 0.7
        private let perRow = 0.05
        private var total: Double { spin + perRow * Double(mock.picks.count) + 0.3 }
        private var pool: [String] { mock.picks.map(\.prospect.name) }

        var body: some View {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    if let odds = mock.lotteryOdds, !odds.isEmpty {
                        LotteryCard(odds: odds,
                                    isOfficial: mock.lotteryIsOfficial,
                                    topPicks: Array(mock.picks.prefix(3)))
                            .padding(.bottom, Theme.Spacing.xs)
                    }
                    if let basis = mock.orderBasis {
                        Text(basis)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 2)
                    }
                    if reveal && !reduceMotion && !finished {
                        TimelineView(.animation(minimumInterval: 1.0 / 14.0)) { ctx in
                            rows(elapsed: ctx.date.timeIntervalSince(start))
                        }
                    } else {
                        rows(elapsed: total)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.md)
            }
            .task(id: reveal) {
                guard reveal else { return }
                if reduceMotion {
                    finished = true
                    onRevealComplete()
                    return
                }
                start = Date()
                finished = false
                try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
                finished = true
                onRevealComplete()
            }
        }

        @ViewBuilder
        private func rows(elapsed: Double) -> some View {
            ForEach(Array(mock.picks.enumerated()), id: \.element.id) { i, pick in
                let locked = finished || elapsed >= spin + perRow * Double(i)
                MockPickRow(pick: pick, locked: locked, shuffleName: shuffleName(i, elapsed))
            }
        }

        private func shuffleName(_ i: Int, _ elapsed: Double) -> String {
            guard !pool.isEmpty else { return "" }
            return pool[(Int(elapsed / 0.08) + i * 3) % pool.count]
        }
    }

    private struct MockPickRow: View {
        let pick: MockPick
        let locked: Bool
        let shuffleName: String

        private var groupColor: Color {
            switch pick.need {
            case "D": return Theme.Palette.defaultAccentAlt
            case "G": return Color(hex: 0x8A5CF6)
            default:  return Theme.Palette.accent
            }
        }

        var body: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(pick.overall)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: 22, alignment: .center)
                CrestView(abbrev: pick.team, size: 30)
                ZStack {
                    Circle().fill(LinearGradient(
                        colors: [Theme.Palette.accent.opacity(0.5), Theme.Palette.accentAlt.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    if locked {
                        if let url = pick.prospect.headshotURL {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() } else { initials }
                            }
                        } else { initials }
                    } else {
                        Image(systemName: "hockey.puck.fill")
                            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 38, height: 38).clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if locked, let flag = pick.prospect.flag { Text(flag).font(.system(size: 12)) }
                        Text(locked ? pick.prospect.name : shuffleName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(locked ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text(locked ? pick.reason : " ")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if locked, let move = pick.movement, move != 0 {
                    HStack(spacing: 1) {
                        Image(systemName: move > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .heavy))
                        Text("\(abs(move))")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(move > 0 ? Theme.Palette.positive : Theme.Palette.negative)
                }
                if locked {
                    Text(pick.prospect.position ?? pick.need)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(groupColor))
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1))
        }

        private var initials: some View {
            Text(pick.prospect.initials)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// Top-of-page draft-lottery card. Pre-lottery: an animated bar chart of each
    /// non-playoff team's chance at the No. 1 pick (worst record = best odds).
    /// Once the order goes official, it flips to the locked top-3 results.
    private struct LotteryCard: View {
        let odds: [LotteryOdds]
        let isOfficial: Bool
        let topPicks: [MockPick]
        @State private var animateIn = false

        private var maxOdds: Double { max(odds.map(\.odds).max() ?? 18.5, 0.1) }

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: isOfficial ? "trophy.fill" : "chart.bar.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isOfficial ? Theme.Palette.moderate : Theme.Palette.accent)
                    Text(isOfficial ? "Lottery Results" : "Draft Lottery Odds")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(isOfficial ? "OFFICIAL" : "PROJECTED")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Palette.border.opacity(0.5)))
                }
                if isOfficial {
                    resultsView
                } else {
                    Text("Chance at the No. 1 pick — if the season ended today")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    oddsChart
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1))
            .task { withAnimation(.easeOut(duration: 0.7)) { animateIn = true } }
        }

        private var oddsChart: some View {
            VStack(spacing: 5) {
                ForEach(odds) { team in
                    HStack(spacing: 8) {
                        Text("\(team.draftSlot)")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(width: 16, alignment: .trailing)
                        CrestView(abbrev: team.abbrev, size: 20)
                        GeometryReader { geo in
                            let frac = team.odds / maxOdds
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.border.opacity(0.4))
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(6, geo.size.width * frac * (animateIn ? 1 : 0)))
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 8)
                        Text(String(format: "%.1f%%", team.odds))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }

        private var resultsView: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let win = topPicks.first {
                    Text("🏆 \(win.teamName) won the No. 1 pick")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(topPicks) { pick in
                        VStack(spacing: 4) {
                            CrestView(abbrev: pick.team, size: 34)
                            Text(Self.ordinal(pick.overall))
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.Palette.accent)
                            Text(pick.prospect.name)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }

        private static func ordinal(_ n: Int) -> String {
            switch n % 100 {
            case 11, 12, 13: return "\(n)th"
            default:
                switch n % 10 {
                case 1: return "\(n)st"
                case 2: return "\(n)nd"
                case 3: return "\(n)rd"
                default: return "\(n)th"
                }
            }
        }
    }

    /// One ranked prospect row: rank medallion (gold/silver/bronze in the top 3),
    /// headshot, flag + name + club line, trend arrow, chevron. Tap → detail sheet.
    private func prospectRow(_ p: Prospect, rank: Int) -> some View {
        PressableButton(action: { detailProspect = p }) {
            HStack(spacing: Theme.Spacing.sm) {
                rankMedallion(rank, showCrest: p.team)
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.Palette.accent.opacity(0.55), Theme.Palette.accentAlt.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    if let url = p.headshotURL {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image { img.resizable().scaledToFill() } else { monogram(p) }
                        }
                    } else {
                        monogram(p)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let flag = p.flag { Text(flag).font(.system(size: 12)) }
                        Text(p.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(p.info?.club.flatMap { $0.isEmpty ? nil : $0 } ?? p.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if let delta = p.rankDelta, delta != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .heavy))
                        Text("\(abs(delta))")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(delta > 0 ? Theme.Palette.positive : Theme.Palette.negative)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((delta > 0 ? Theme.Palette.positive : Theme.Palette.negative).opacity(0.12))
                    .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(rank <= 3 && p.team == nil ? medallionColor(rank).opacity(0.5) : Theme.Palette.border,
                              lineWidth: rank <= 3 && p.team == nil ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Draft board: numbered medallion (podium colors for 1–3). My Team: crest.
    @ViewBuilder
    private func rankMedallion(_ rank: Int, showCrest team: String?) -> some View {
        if let team, !team.isEmpty {
            CrestView(abbrev: team, size: 28)
                .frame(width: 30)
        } else {
            Text("\(rank)")
                .font(.system(size: rank > 99 ? 11 : 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(rank <= 3
                        ? AnyShapeStyle(LinearGradient(colors: [medallionColor(rank), medallionColor(rank).opacity(0.7)],
                                                       startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Theme.Palette.accent))
                )
                .shadow(color: rank <= 3 ? medallionColor(rank).opacity(0.4) : .clear, radius: 4, y: 1)
        }
    }

    private func medallionColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: 0xE8A200)   // gold
        case 2: return Color(hex: 0x9BA6B2)   // silver
        case 3: return Color(hex: 0xB4713C)   // bronze
        default: return Theme.Palette.accent
        }
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
