import SwiftUI

/// Per-story watched tracking for the recap deck (shared with the News feed's
/// "N new stories" counter). JSON-encoded array in AppStorage — URLs can
/// contain commas, so no joined-string tricks. FIFO-capped.
enum WatchedStories {
    static let key = "watchedStoryItemURLs"

    static func decode(_ raw: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
    }

    static func encode(_ urls: [String]) -> String {
        let capped = Array(urls.suffix(300))
        guard let data = try? JSONEncoder().encode(capped) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

/// The recap as a story deck, rebuilt in the app's card language: one floating
/// rounded card per story over drifting team-color blobs, with a center-cropped
/// photo (slow Ken Burns drift), headline, and blurb.
///
/// The deck only plays stories the user hasn't watched — each slide is marked
/// watched the moment it appears, so a half-watched deck never replays. When
/// everything is watched it replays the whole current set (rewatch mode).
///
/// Gestures: tap right/left thirds = next/previous · long-press = AI summary
/// (pauses the deck, same ring animation as the feed) · drag down = dismiss.
struct NewsStoryView: View {
    let digests: [NewsDigest]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PremiumStore.self) private var premium
    @AppStorage(WatchedStories.key) private var watchedRaw = "[]"

    @State private var deck: [DigestItem] = []   // frozen on appear (filtering live would yank slides)
    @State private var index = 0
    @State private var progress = 0.0
    @State private var pressing = false          // long-press in flight → paused
    @State private var summaryItem: DigestItem?
    @State private var showPaywall = false
    @State private var dragOffset: CGFloat = 0
    @State private var kenBurns = false
    @State private var shown = false             // hero expand/collapse
    @State private var closing = false           // brief gather beat before the zoom-out
    @State private var direction = 1             // +1 forward, -1 back (slide anim)

    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    // MARK: - Deck

    /// Unique unwatched stories across the digests, newest edition first;
    /// all stories when everything has been seen (rewatch mode).
    private func buildDeck() -> [DigestItem] {
        var seen = Set<String>()
        var all: [DigestItem] = []
        for d in digests {
            for it in d.items where seen.insert(it.url).inserted {
                all.append(it)
            }
        }
        let watched = Set(WatchedStories.decode(watchedRaw))
        let fresh = all.filter { !watched.contains($0.url) }
        return Array((fresh.isEmpty ? all : fresh).prefix(20))
    }

    /// Adaptive per-slide duration: longer blurbs get more reading time.
    private func duration(_ it: DigestItem) -> Double {
        8 + min(4, Double(it.blurb.count) / 60.0)
    }

    private var paused: Bool {
        pressing || summaryItem != nil || showPaywall || dragOffset > 4
    }

    // MARK: - Body

    /// Direction-aware slide transition: forward enters from the right,
    /// rewinding enters from the left.
    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction >= 0 ? .trailing : .leading)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94)),
            removal: .move(edge: direction >= 0 ? .leading : .trailing)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.94)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ambientBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    chrome(count: deck.count)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)

                    ZStack {
                        if deck.indices.contains(index) {
                            slideCard(deck[index], size: geo.size)
                                .id(deck[index].url)
                                .transition(slideTransition)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.md)
                }
            }
            // iOS 17 fallback entrance: the app's floating-card language.
            // (On iOS 18+ the native zoom drives the whole move; `shown` stays
            // visually inert there because it's set without animation.)
            // `closing` adds a short gather beat before the zoom-out on close.
            .opacity(shown ? (closing ? 0.92 : 1) : 0)
            .scaleEffect(shown ? (closing ? 0.95 : 1) : 0.94)
        }
        .statusBarHidden()
        .onReceive(timer) { _ in tick() }
        .onChange(of: index) { _, newValue in
            markWatched(at: newValue)
            restartKenBurns()
        }
        .onAppear {
            // fullScreenCover reuses @State across presentations — always restart.
            index = 0
            progress = 0
            dragOffset = 0
            direction = 1
            shown = false
            closing = false
            deck = buildDeck()
            if deck.isEmpty { dismiss() }
            markWatched(at: 0)
            if #available(iOS 18.0, *) {
                shown = true                    // zoom transition owns the entrance
            } else {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                              : .spring(response: 0.55, dampingFraction: 0.85)) {
                    shown = true
                }
            }
            restartKenBurns()
        }
        .floatingCard(item: $summaryItem) { item in
            NewsSummarySheet(item: item)
        }
        .floatingCard(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Ambient background (the app's blobs, night mode)

    private var ambientBackground: some View {
        ZStack {
            Color(hex: 0x0B0E13)
            if reduceMotion {
                blobs(t: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    blobs(t: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func blobs(t: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.accent.opacity(0.45))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: -130 + 24 * sin(t / 7), y: -260 + 18 * cos(t / 9))
            Circle()
                .fill(Theme.Palette.accentAlt.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 150 + 20 * cos(t / 8), y: 240 + 22 * sin(t / 6))
        }
    }

    // MARK: - Top chrome (progress + paused + close)

    private func chrome(count: Int) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                ForEach(0..<max(count, 1), id: \.self) { i in
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.white)
                                    .frame(width: g.size.width * fill(i))
                            }
                    }
                    .frame(height: 4)
                }
            }
            HStack {
                if paused {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill").font(.system(size: 9, weight: .heavy))
                        Text("PAUSED").font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.14))
                    .clipShape(Capsule())
                    .transition(.opacity)
                }
                Spacer()
                Button { collapse() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .animation(.easeOut(duration: 0.2), value: paused)
        }
    }

    private func fill(_ i: Int) -> Double { i < index ? 1 : (i == index ? min(progress, 1) : 0) }

    // MARK: - Slide card

    private func slideCard(_ it: DigestItem, size: CGSize) -> some View {
        itemSlide(it)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            .overlay {
                if pressing {
                    AnimatedGradientRing(cornerRadius: 32)
                    Label("Hold for AI summary", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
            .scaleEffect(pressing ? 0.97 : 1)
            .offset(y: dragOffset)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pressing)
            // Long-press = AI summary (pauses the deck while pressed).
            .onLongPressGesture(minimumDuration: 0.55, maximumDistance: 40) {
                fireSummary(it)
            } onPressingChanged: { pressing = $0 }
            // Quick tap: right two-thirds advances, left third rewinds.
            .gesture(
                SpatialTapGesture().onEnded { value in
                    if value.location.x < size.width * 0.33 { prev() } else { next() }
                }
            )
            // Drag down to dismiss, with rubber-banding.
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { v in
                        dragOffset = v.translation.height > 0
                            ? v.translation.height
                            : v.translation.height / 6
                    }
                    .onEnded { v in
                        if v.translation.height > 120 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dragOffset = 0
                            }
                            collapse()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
    }

    private func fireSummary(_ it: DigestItem) {
        Haptics.tap()
        if premium.isPremium { summaryItem = it } else { showPaywall = true }
    }

    // MARK: - Item slide

    private func itemSlide(_ it: DigestItem) -> some View {
        GeometryReader { geo in
            let photoHeight = geo.size.height * 0.52
            VStack(spacing: 0) {
                // Photo: center-cropped into its box, with a slow Ken Burns drift.
                Color.clear
                    .frame(height: photoHeight)
                    .overlay {
                        Group {
                            if let url = it.image {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        photoPlaceholder
                                    }
                                }
                            } else {
                                photoPlaceholder
                            }
                        }
                        .scaleEffect(kenBurns && !reduceMotion ? 1.09 : 1.0)
                    }
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, Color(hex: 0x10141B).opacity(0.9)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 90)
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(it.tag.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color(hex: 0x10141B))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.white)
                                .clipShape(Capsule())
                            Text(it.source)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .padding(Theme.Spacing.md)
                    }

                // Content panel.
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(it.headline)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(it.blurb)
                        .font(.system(size: 15.5))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(3)
                        .lineLimit(6)
                        .minimumScaleFactor(0.9)

                    Spacer(minLength: 0)

                    Label("Hold anywhere for an AI summary", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)

                    Button {
                        if let u = URL(string: it.url) { openURL(u) }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Read full article")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                startPoint: .leading, endPoint: .trailing))
                        )
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x10141B))
            }
        }
    }

    private var photoPlaceholder: some View {
        LinearGradient(colors: [Theme.Palette.accent.opacity(0.75), Theme.Palette.accentAlt.opacity(0.45)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                Image(systemName: "hockey.puck.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.45))
            )
    }

    // MARK: - Advance

    private func tick() {
        guard !deck.isEmpty, !paused, deck.indices.contains(index) else { return }
        progress += 0.04 / duration(deck[index])
        if progress >= 1 { next() }
    }

    private func next() {
        if index < deck.count - 1 {
            Haptics.tap()
            direction = 1
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index += 1 }
            progress = 0
        } else {
            collapse()
        }
    }

    private func prev() {
        if index > 0 {
            Haptics.tap()
            direction = -1
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index -= 1 }
        }
        progress = 0
    }

    /// Close the deck. iOS 18's zoom shrinks the screen back into the launcher
    /// card by itself — preceded by a short "gather" beat so the close reads
    /// slower and more deliberate. The iOS 17 fallback fades the floating-card way.
    private func collapse() {
        if #available(iOS 18.0, *) {
            guard !closing else { return }
            if reduceMotion {
                dismiss()
                return
            }
            withAnimation(.easeIn(duration: 0.22)) { closing = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 210_000_000)
                dismiss()
            }
            return
        }
        guard shown else { return }
        withAnimation(reduceMotion ? .easeIn(duration: 0.15) : .easeIn(duration: 0.2)) {
            shown = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 210_000_000)
            dismiss()
        }
    }

    /// Restart the slow photo zoom for the slide that just appeared.
    private func restartKenBurns() {
        guard !reduceMotion else { return }
        kenBurns = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.linear(duration: 9)) { kenBurns = true }
        }
    }

    /// A slide counts as watched the moment it appears — a half-watched deck
    /// never replays the stories the user already saw.
    private func markWatched(at i: Int) {
        guard deck.indices.contains(i) else { return }
        var urls = WatchedStories.decode(watchedRaw)
        let url = deck[i].url
        if !urls.contains(url) {
            urls.append(url)
            watchedRaw = WatchedStories.encode(urls)
        }
    }
}
