import SwiftUI

/// Story-style walkthrough of the day's digest: an animated intro slide, then
/// one slide per top story (media region on top, text panel below — the media
/// region is the future video slot). Auto-advances with adaptive timing; hold
/// anywhere to pause, tap left/right to navigate, swipe down to dismiss.
/// Completing the deck marks the digest watched (the News-tab ring goes away).
struct NewsStoryView: View {
    let digests: [NewsDigest]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("watchedStoryDigestIds") private var watchedIds = ""

    @State private var index = 0
    @State private var progress = 0.0
    @State private var paused = false
    @State private var pressStart: Date?

    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    private enum Slide: Identifiable {
        case intro(String, [String], String?)
        case item(DigestItem)
        var id: String { switch self { case .intro(let t, _, _): return "intro-\(t)"; case .item(let it): return it.url } }
    }

    private var slides: [Slide] {
        var s: [Slide] = []
        if let first = digests.first, let kp = first.keyPoints, !kp.isEmpty {
            s.append(.intro(first.title, kp, first.asOf))
        }
        for d in digests {
            for it in d.items.prefix(5) { s.append(.item(it)) }
        }
        return s
    }

    /// Adaptive per-slide duration: longer blurbs get more reading time.
    private func duration(_ slide: Slide) -> Double {
        switch slide {
        case .intro: return 8
        case .item(let it): return 8 + min(4, Double(it.blurb.count) / 60.0)
        }
    }

    var body: some View {
        let slides = self.slides
        return ZStack {
            Color.black.ignoresSafeArea()

            if slides.indices.contains(index) {
                slideView(slides[index])
                    .id(slides[index].id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                    .ignoresSafeArea(edges: .top)
            }

            // Touch layer: hold = pause, quick tap = navigate, drag down = dismiss.
            Color.clear
                .contentShape(Rectangle())
                .gesture(holdTapGesture(slides))

            VStack(spacing: 0) {
                progressBar(count: slides.count)
                    .padding(.horizontal, Theme.Spacing.md).padding(.top, Theme.Spacing.sm)
                HStack {
                    if paused {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.black.opacity(0.35)).clipShape(Capsule())
                            .padding(.leading, Theme.Spacing.md)
                            .transition(.opacity)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white).padding(10).background(.black.opacity(0.35)).clipShape(Circle())
                    }
                    .padding(.trailing, Theme.Spacing.md)
                }
                .padding(.top, Theme.Spacing.sm)
                .animation(.easeOut(duration: 0.2), value: paused)
                Spacer()
            }
        }
        .onReceive(timer) { _ in tick(slides) }
        .onChange(of: index) { _, newValue in
            if newValue >= slides.count - 1 { markWatched() }
        }
        .statusBarHidden()
        .onAppear {
            if slides.isEmpty { dismiss() }
            if slides.count == 1 { markWatched() }
        }
    }

    // MARK: - Gestures

    private func holdTapGesture(_ slides: [Slide]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressStart == nil {
                    pressStart = Date()
                    withAnimation { paused = true }
                }
            }
            .onEnded { v in
                let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                pressStart = nil
                withAnimation { paused = false }
                if v.translation.height > 90 {
                    dismiss()
                } else if held < 0.25 && abs(v.translation.width) < 20 && abs(v.translation.height) < 20 {
                    if v.location.x < UIScreen.main.bounds.width * 0.35 { prev(slides) } else { next(slides) }
                }
            }
    }

    // MARK: - Slides

    @ViewBuilder
    private func slideView(_ slide: Slide) -> some View {
        switch slide {
        case .intro(let title, let points, let asOf):
            introSlide(title: title, points: points, asOf: asOf)
        case .item(let it):
            itemSlide(it)
        }
    }

    private func introSlide(title: String, points: [String], asOf: String?) -> some View {
        ZStack {
            // Slowly drifting gradient backdrop.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt, Theme.Palette.accent.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .hueRotation(.degrees(sin(t / 4) * 22))
                    .overlay(
                        RadialGradient(colors: [.white.opacity(0.12), .clear],
                                       center: UnitPoint(x: 0.5 + 0.3 * cos(t / 5), y: 0.3 + 0.2 * sin(t / 3)),
                                       startRadius: 10, endRadius: 320)
                    )
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Spacer()
                HStack(spacing: Theme.Spacing.xs) {
                    GoalLightIcon(height: 18)
                    Text(title.uppercased())
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .kerning(1.5)
                }
                .staggeredEntrance(index: 0)
                Text("Today's\nTop Stories")
                    .font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .staggeredEntrance(index: 1)
                if let asOf {
                    Text("As of \(asOf)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .staggeredEntrance(index: 2)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                            PuckDot(size: 12).padding(.top, 5)
                            Text(p).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .staggeredEntrance(index: min(i + 3, 9))
                    }
                }
                .padding(.top, Theme.Spacing.xs)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func itemSlide(_ it: DigestItem) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Media region (future video slot).
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let url = it.image {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    mediaPlaceholder(it.tag)
                                }
                            }
                        } else {
                            mediaPlaceholder(it.tag)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height * 0.46)
                    .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                        .frame(height: 80)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
                .frame(height: geo.size.height * 0.46)

                // Content panel — text can never clip off-screen.
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.xs) {
                        chip(it.tag)
                        Text(it.source).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Text(it.headline)
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(it.blurb)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineSpacing(3)
                        .lineLimit(7)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Button { if let u = URL(string: it.url) { openURL(u) } } label: {
                        HStack { Text("Read article"); Image(systemName: "arrow.up.right") }
                            .font(Theme.Font.headline()).foregroundStyle(.black)
                            .padding(.horizontal, Theme.Spacing.lg).padding(.vertical, Theme.Spacing.sm)
                            .background(.white).clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Theme.Spacing.lg)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            }
        }
    }

    private func mediaPlaceholder(_ tag: String) -> some View {
        LinearGradient(colors: [Theme.Palette.accent.opacity(0.7), Theme.Palette.accentAlt.opacity(0.4)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "hockey.puck.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.5)))
    }

    private func progressBar(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: g.size.width * fill(i))
                        }
                }
                .frame(height: 3)
            }
        }
    }

    private func fill(_ i: Int) -> Double { i < index ? 1 : (i == index ? min(progress, 1) : 0) }

    private func chip(_ tag: String) -> some View {
        Text(tag.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 3).background(.white).clipShape(Capsule())
    }

    // MARK: - Advance

    private func tick(_ slides: [Slide]) {
        guard !slides.isEmpty, !paused, slides.indices.contains(index) else { return }
        progress += 0.04 / duration(slides[index])
        if progress >= 1 { next(slides) }
    }

    private func next(_ slides: [Slide]) {
        if index < slides.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { index += 1 }
            progress = 0
        } else {
            markWatched()
            dismiss()
        }
    }

    private func prev(_ slides: [Slide]) {
        if index > 0 { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { index -= 1 } }
        progress = 0
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
