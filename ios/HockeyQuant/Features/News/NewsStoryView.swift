import SwiftUI

/// The daily recap as a story deck, rebuilt in the app's card language: each
/// slide is a floating rounded card over drifting team-color blobs. A cover
/// slide leads with the day's key points, then one card per top story with a
/// center-cropped photo (slow Ken Burns drift), headline, and blurb.
///
/// Gestures: tap right/left thirds = next/previous · long-press = AI summary
/// (pauses the deck, same ring animation as the feed) · drag down = dismiss.
/// Completing the deck marks the digest watched (the News-tab ring goes away).
struct NewsStoryView: View {
    let digests: [NewsDigest]
    /// Global frame of the "Watch today's recap" card — the deck morphs out of
    /// this rect on present and collapses back into it on dismiss.
    var originFrame: CGRect = .zero

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PremiumStore.self) private var premium
    @AppStorage("watchedStoryDigestIds") private var watchedIds = ""

    @State private var index = 0
    @State private var progress = 0.0
    @State private var pressing = false          // long-press in flight → paused
    @State private var summaryItem: DigestItem?
    @State private var showPaywall = false
    @State private var dragOffset: CGFloat = 0
    @State private var kenBurns = false
    @State private var shown = false             // hero expand/collapse
    @State private var direction = 1             // +1 forward, -1 back (slide anim)

    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    // MARK: - Slides

    private enum Slide: Identifiable {
        case cover(title: String, points: [String], asOf: String?)
        case item(DigestItem)
        var id: String {
            switch self {
            case .cover(let t, _, _): return "cover-\(t)"
            case .item(let it): return it.url
            }
        }
    }

    private var slides: [Slide] {
        var s: [Slide] = []
        if let first = digests.first, let kp = first.keyPoints, !kp.isEmpty {
            s.append(.cover(title: first.title, points: kp, asOf: first.asOf))
        }
        for d in digests {
            for it in d.items.prefix(5) { s.append(.item(it)) }
        }
        return s
    }

    /// Adaptive per-slide duration: longer blurbs get more reading time.
    private func duration(_ slide: Slide) -> Double {
        switch slide {
        case .cover: return 9
        case .item(let it): return 8 + min(4, Double(it.blurb.count) / 60.0)
        }
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
        let slides = self.slides
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let hasOrigin = originFrame != .zero && frame.width > 0 && frame.height > 0
            let heroOffset: CGSize = hasOrigin ? CGSize(
                width: originFrame.midX - frame.midX,
                height: originFrame.midY - frame.midY) : .zero
            let sx: CGFloat = hasOrigin ? max(originFrame.width / frame.width, 0.02) : 0.08
            let sy: CGFloat = hasOrigin ? max(originFrame.height / frame.height, 0.02) : 0.08

            ZStack {
                ambientBackground

                VStack(spacing: 0) {
                    chrome(count: slides.count)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, 58)

                    ZStack {
                        if slides.indices.contains(index) {
                            slideCard(slides[index], size: geo.size)
                                .id(slides[index].id)
                                .transition(slideTransition)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.md)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: shown ? 48 : Theme.Radius.lg,
                                        style: .continuous))
            // The team-color flood that filled the launcher rides the morphing
            // rect, then dissolves to reveal the deck (and back on collapse).
            .overlay {
                RoundedRectangle(cornerRadius: shown ? 48 : Theme.Radius.lg, style: .continuous)
                    .fill(.clear)
                    .overlay {
                        AnimatedTeamBackground(
                            colors: [Theme.Palette.accentAlt, Theme.Palette.accent, Theme.Palette.accentAlt],
                            base: Theme.Palette.accent,
                            radiusFactor: 1.0,
                            speed: 4
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: shown ? 48 : Theme.Radius.lg,
                                                style: .continuous))
                    .opacity(shown ? 0 : 1)
                    .allowsHitTesting(false)
            }
            // The rect-morph itself: the card's exact frame ↔ full screen,
            // stretching horizontally and vertically together.
            .scaleEffect(x: shown ? 1 : sx, y: shown ? 1 : sy)
            .offset(shown ? .zero : heroOffset)
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)   // feed stays visible behind the hero moves
        .statusBarHidden()
        .onReceive(timer) { _ in tick(slides) }
        .onChange(of: index) { _, newValue in
            if newValue >= slides.count - 1 { markWatched() }
            restartKenBurns()
        }
        .onAppear {
            // fullScreenCover reuses @State across presentations — always restart.
            index = 0
            progress = 0
            dragOffset = 0
            direction = 1
            shown = false
            if slides.isEmpty { dismiss() }
            if slides.count == 1 { markWatched() }
            withAnimation(reduceMotion ? .easeOut(duration: 0.18)
                          : .spring(response: 0.5, dampingFraction: 0.82)) {
                shown = true
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

    @ViewBuilder
    private func slideCard(_ slide: Slide, size: CGSize) -> some View {
        Group {
            switch slide {
            case .cover(let title, let points, let asOf):
                coverSlide(title: title, points: points, asOf: asOf)
            case .item(let it):
                itemSlide(it)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .overlay {
            if pressing, isSummarizable(slide) {
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
            fireSummary(slide)
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

    private func isSummarizable(_ slide: Slide) -> Bool {
        if case .item = slide { return true }
        return false
    }

    private func fireSummary(_ slide: Slide) {
        guard case .item(let it) = slide else { return }
        Haptics.tap()
        if premium.isPremium { summaryItem = it } else { showPaywall = true }
    }

    // MARK: - Cover slide

    private func coverSlide(title: String, points: [String], asOf: String?) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    RadialGradient(colors: [.white.opacity(0.16), .clear],
                                   center: UnitPoint(x: 0.5 + 0.35 * cos(t / 6),
                                                     y: 0.28 + 0.22 * sin(t / 4)),
                                   startRadius: 20, endRadius: 340)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.xs) {
                    ZStack {
                        Circle().fill(.white.opacity(0.18))
                        Image(systemName: "hockey.puck.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1.4)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .staggeredEntrance(index: 0)

                Text("Today's\nTop Stories")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .staggeredEntrance(index: 1)

                if let asOf {
                    BandPill(text: "As of \(asOf)", systemImage: "clock")
                        .staggeredEntrance(index: 2)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(points.prefix(5).enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            Text("\(i + 1)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.Palette.accent)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.white))
                            Text(p)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .staggeredEntrance(index: min(i + 3, 9))
                    }
                }
                .padding(.top, Theme.Spacing.xs)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Text("Tap to read the stories")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .staggeredEntrance(index: 6)
            }
            .padding(Theme.Spacing.lg)
        }
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

    private func tick(_ slides: [Slide]) {
        guard !slides.isEmpty, !paused, slides.indices.contains(index) else { return }
        progress += 0.04 / duration(slides[index])
        if progress >= 1 { next() }
    }

    private func next() {
        let slides = self.slides
        if index < slides.count - 1 {
            Haptics.tap()
            direction = 1
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { index += 1 }
            progress = 0
        } else {
            markWatched()
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

    /// Shrink the deck back into the launcher card, then dismiss the cover.
    private func collapse() {
        guard shown else { return }
        withAnimation(reduceMotion ? .easeIn(duration: 0.15)
                      : .spring(response: 0.42, dampingFraction: 0.88)) {
            shown = false
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)
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

    private func markWatched() {
        guard let id = digests.first?.id else { return }
        var ids = watchedIds.split(separator: ",").map(String.init)
        if !ids.contains(id) {
            ids.append(id)
            watchedIds = ids.suffix(20).joined(separator: ",")
        }
    }
}
