import SwiftUI

/// Season Wrapped: a Spotify-Wrapped-style recap of the user's season — big
/// count-up numbers on floating cards over drifting team-color blobs, ending
/// in a shareable summary card. Presented with the App Store zoom from the
/// banner on Play's My Stats segment.
struct SeasonWrappedView: View {
    let stats: UserStats
    let xp: Int
    let picks: [UserPick]
    let modelAccuracy: Double?    // official model season accuracy (nil = unknown)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AuthStore.self) private var auth

    @State private var index = 0
    @State private var progress = 0.0
    @State private var direction = 1
    @State private var dragOffset: CGFloat = 0
    @State private var shown = false
    @State private var closing = false
    @State private var reveal = false     // per-slide count-up trigger

    private let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()
    private let slideDuration = 6.5

    // MARK: - Derived season facts

    private var userAccuracy: Double {
        stats.picksMade > 0 ? Double(stats.picksCorrect) / Double(stats.picksMade) * 100 : 0
    }

    private var tier: GMTier { GMTier.current(forXp: xp) }

    /// A correct call the model got wrong — the boldest night of the season.
    private var boldestCall: UserPick? {
        picks.filter { $0.correct == true && $0.modelPick != nil && $0.pick != $0.modelPick }
            .max { $0.gameDate < $1.gameDate }
    }

    /// (away, home) parsed from "yyyy-MM-dd-AWY-HOM".
    private func matchup(of pick: UserPick) -> (away: String, home: String)? {
        let parts = pick.gameId.split(separator: "-").map(String.init)
        guard parts.count >= 5 else { return nil }
        return (parts[parts.count - 2], parts[parts.count - 1])
    }

    private var mostPicked: (team: String, count: Int)? {
        let counts = Dictionary(grouping: picks, by: \.pick).mapValues(\.count)
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (top.key, top.value)
    }

    // MARK: - Slides

    private enum Slide: Int, CaseIterable, Identifiable {
        case cover, volume, record, versusModel, streak, boldest, ride, trophies, finale
        var id: Int { rawValue }
    }

    private var slides: [Slide] {
        Slide.allCases.filter { slide in
            switch slide {
            case .boldest: return boldestCall != nil
            case .ride: return mostPicked != nil
            case .versusModel: return stats.picksMade > 0
            default: return true
            }
        }
    }

    // MARK: - Body

    var body: some View {
        let slides = self.slides
        GeometryReader { geo in
            ZStack {
                ambient.ignoresSafeArea()

                VStack(spacing: 0) {
                    chrome(count: slides.count)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.xs)

                    ZStack {
                        if slides.indices.contains(index) {
                            card(for: slides[index])
                                .id(slides[index].id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: direction >= 0 ? .trailing : .leading)
                                        .combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                                    removal: .move(edge: direction >= 0 ? .leading : .trailing)
                                        .combined(with: .opacity).combined(with: .scale(scale: 0.94))))
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.md)
                }
            }
            .opacity(shown ? (closing ? 0.92 : 1) : 0)
            .scaleEffect(shown ? (closing ? 0.95 : 1) : 0.94)
        }
        .statusBarHidden()
        .onReceive(timer) { _ in tick(slides) }
        .onChange(of: index) { _, _ in restartReveal() }
        .onAppear {
            index = 0; progress = 0; direction = 1; closing = false; shown = false
            if #available(iOS 18.0, *) { shown = true }
            else { withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { shown = true } }
            restartReveal()
        }
    }

    private var ambient: some View {
        ZStack {
            Color(hex: 0x0B0E13)
            if reduceMotion {
                wrappedBlobs(t: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    wrappedBlobs(t: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func wrappedBlobs(t: TimeInterval) -> some View {
        ZStack {
            Circle().fill(Theme.Palette.accent.opacity(0.5))
                .frame(width: 360, height: 360).blur(radius: 85)
                .offset(x: -140 + 26 * sin(t / 6), y: -230 + 20 * cos(t / 8))
            Circle().fill(Theme.Palette.accentAlt.opacity(0.4))
                .frame(width: 320, height: 320).blur(radius: 95)
                .offset(x: 150 + 22 * cos(t / 7), y: 250 + 24 * sin(t / 5))
        }
    }

    private func chrome(count: Int) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: 5) {
                ForEach(0..<max(count, 1), id: \.self) { i in
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.22))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: g.size.width * (i < index ? 1 : (i == index ? min(progress, 1) : 0)))
                            }
                    }
                    .frame(height: 4)
                }
            }
            HStack {
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
        }
    }

    // MARK: - Slide cards

    @ViewBuilder
    private func card(for slide: Slide) -> some View {
        Group {
            switch slide {
            case .cover: coverSlide
            case .volume: volumeSlide
            case .record: recordSlide
            case .versusModel: versusSlide
            case .streak: streakSlide
            case .boldest: boldestSlide
            case .ride: rideSlide
            case .trophies: trophySlide
            case .finale: finaleSlide
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
        .offset(y: dragOffset)
        .gesture(
            SpatialTapGesture().onEnded { v in
                if v.location.x < 130 { prev() } else { next() }
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { v in
                    dragOffset = v.translation.height > 0 ? v.translation.height : v.translation.height / 6
                }
                .onEnded { v in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { dragOffset = 0 }
                    if v.translation.height > 120 { collapse() }
                }
        )
    }

    /// Slide scaffold: dark card, kicker line, huge stat, supporting line.
    private func statSlide<Content: View>(kicker: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color(hex: 0x10141B)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(kicker.uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.6))
                    .staggeredEntrance(index: 0)
                Spacer()
                content()
                Spacer()
                Text("HOCKEYQUANT · \(Season.current.id) WRAPPED")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func bigNumber(_ value: Int, tint: Color = .white) -> some View {
        Text("\(reveal ? value : 0)")
            .font(.system(size: 96, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .contentTransition(.numericText(value: Double(reveal ? value : 0)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var coverSlide: some View {
        ZStack {
            LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 84, height: 84)
                    Image(systemName: "hockey.puck.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .staggeredEntrance(index: 0)
                Text(Season.current.id)
                    .font(.system(size: 15, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .staggeredEntrance(index: 1)
                Text("Your Season,\nWrapped")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .staggeredEntrance(index: 2)
                if let name = auth.username {
                    BandPill(text: name, systemImage: "person.fill")
                        .staggeredEntrance(index: 3)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("Tap to relive it")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, Theme.Spacing.md)
                .staggeredEntrance(index: 4)
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var volumeSlide: some View {
        statSlide(kicker: "You showed up") {
            VStack(alignment: .leading, spacing: 6) {
                bigNumber(stats.picksMade)
                Text("calls made this season")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Every night you stepped up to the glass and made a call.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var recordSlide: some View {
        statSlide(kicker: "Your record") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    bigNumber(stats.picksCorrect, tint: Theme.Palette.strong)
                    Text("–")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(reveal ? max(stats.picksMade - stats.picksCorrect, 0) : 0)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                }
                Text(String(format: "%.1f%% accuracy", reveal ? userAccuracy : 0))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                SplitBar(leftFraction: userAccuracy / 100,
                         leftColor: Theme.Palette.strong,
                         rightColor: .white.opacity(0.15), height: 8)
                    .frame(maxWidth: 240)
            }
        }
    }

    private var versusSlide: some View {
        statSlide(kicker: "You vs the machine") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                bigNumber(stats.beatsModel, tint: Theme.Palette.accentAlt)
                Text("nights you outcalled the AI")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let model = modelAccuracy {
                    VStack(alignment: .leading, spacing: 8) {
                        accuracyRow(label: "You", pct: userAccuracy, tint: Theme.Palette.accentAlt)
                        accuracyRow(label: "Model", pct: model, tint: .white.opacity(0.5))
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
            }
        }
    }

    private func accuracyRow(label: String, pct: Double, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 48, alignment: .leading)
            SplitBar(leftFraction: (reveal ? pct : 0) / 100, leftColor: tint,
                     rightColor: .white.opacity(0.12), height: 8)
                .frame(maxWidth: 190)
            Text(String(format: "%.1f%%", pct))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var streakSlide: some View {
        statSlide(kicker: "When you were hot") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("🔥")
                        .font(.system(size: 64))
                        .scaleEffect(reveal ? 1 : 0.3)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: reveal)
                    bigNumber(stats.bestStreak, tint: Color(hex: 0xFF9500))
                }
                Text("correct calls in a row — your longest heater")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var boldestSlide: some View {
        if let bold = boldestCall {
            statSlide(kicker: "Your boldest call") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let m = matchup(of: bold) {
                        HStack(spacing: -10) {
                            CrestView(abbrev: m.away, size: 64)
                            CrestView(abbrev: m.home, size: 64)
                        }
                        .staggeredEntrance(index: 1)
                    }
                    Text("You took \(bold.pick).")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("The model said \(bold.modelPick ?? "otherwise"). You were right — \(prettyDate(bold.gameDate)).")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    StatusPill(text: "BEAT THE AI", color: Theme.Palette.strong, solid: true)
                }
            }
        }
    }

    @ViewBuilder
    private var rideSlide: some View {
        if let ride = mostPicked {
            statSlide(kicker: "You rode with") {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    CrestView(abbrev: ride.team, size: 96)
                        .scaleEffect(reveal ? 1 : 0.4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.65), value: reveal)
                    Text(TeamInfo.lookup(ride.team).name)
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("You backed them \(ride.count) time\(ride.count == 1 ? "" : "s") — more than any other team.")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var trophySlide: some View {
        statSlide(kicker: "The trophy shelf") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Color(hex: 0xE8A200))
                        .scaleEffect(reveal ? 1 : 0.3)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: reveal)
                    bigNumber(stats.stanleyCups, tint: Color(hex: 0xE8A200))
                }
                Text("Stanley Cups lifted")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: tier.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tier.color)
                    Text("Finished the season as a \(tier.name)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private var finaleSlide: some View {
        ZStack {
            LinearGradient(colors: [Theme.Palette.accentAlt, Theme.Palette.accent],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                Text("That's a wrap on \(Season.current.id).")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .staggeredEntrance(index: 0)
                summaryMini
                    .staggeredEntrance(index: 1)
                Spacer()
                if let image = renderShareCard() {
                    ShareLink(item: image,
                              preview: SharePreview("My \(Season.current.id) HockeyQuant Wrapped", image: image)) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share your Wrapped")
                        }
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white)
                        .clipShape(Capsule())
                    }
                    .staggeredEntrance(index: 2)
                }
                Button { collapse() } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.bottom, Theme.Spacing.xs)
                .staggeredEntrance(index: 3)
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var summaryMini: some View {
        VStack(spacing: Theme.Spacing.xs) {
            summaryRow("Calls", "\(stats.picksMade)")
            summaryRow("Record", "\(stats.picksCorrect)–\(max(stats.picksMade - stats.picksCorrect, 0))")
            summaryRow("Accuracy", String(format: "%.1f%%", userAccuracy))
            summaryRow("Beat the AI", "\(stats.beatsModel)×")
            summaryRow("Cups", "\(stats.stanleyCups)")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: 280)
        .background(.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Share card

    @MainActor
    private func renderShareCard() -> Image? {
        let renderer = ImageRenderer(content: WrappedShareCard(
            username: auth.username, stats: stats, accuracy: userAccuracy,
            tierName: tier.name, mostPicked: mostPicked?.team))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }

    // MARK: - Advance / dismiss

    private func tick(_ slides: [Slide]) {
        guard !slides.isEmpty, dragOffset <= 4, !closing, slides.indices.contains(index) else { return }
        progress += 0.04 / slideDuration
        if progress >= 1 {
            // The finale holds for the share moment — only a tap closes it.
            if index < slides.count - 1 { next() } else { progress = 1 }
        }
    }

    private func next() {
        if index < slides.count - 1 {
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

    private func restartReveal() {
        reveal = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.9)) { reveal = true }
        }
    }

    private func collapse() {
        if #available(iOS 18.0, *) {
            guard !closing else { return }
            if reduceMotion { dismiss(); return }
            withAnimation(.easeIn(duration: 0.22)) { closing = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 210_000_000)
                dismiss()
            }
            return
        }
        guard shown else { return }
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 210_000_000)
            dismiss()
        }
    }

    private func prettyDate(_ iso: String) -> String {
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        let outFmt = DateFormatter(); outFmt.dateFormat = "MMM d"
        guard let d = inFmt.date(from: iso) else { return iso }
        return outFmt.string(from: d)
    }
}

// MARK: - Shareable summary card

/// The social artifact: a branded snapshot of the season, rendered offscreen.
struct WrappedShareCard: View {
    let username: String?
    let stats: UserStats
    let accuracy: Double
    let tierName: String
    let mostPicked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "hockey.puck.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("HOCKEYQUANT · \(Season.current.id) WRAPPED")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(username.map { "\($0)'s season" } ?? "My season")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                shareRow("Calls made", "\(stats.picksMade)")
                shareRow("Record", "\(stats.picksCorrect)–\(max(stats.picksMade - stats.picksCorrect, 0))")
                shareRow("Accuracy", String(format: "%.1f%%", accuracy))
                shareRow("Beat the AI", "\(stats.beatsModel) nights")
                shareRow("Longest streak", "\(stats.bestStreak) straight")
                shareRow("Stanley Cups", "\(stats.stanleyCups)")
                if let team = mostPicked {
                    shareRow("Rode with", TeamInfo.lookup(team).name)
                }
                shareRow("Final rank", tierName)
            }
            .padding(16)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack {
                Text("How did your season stack up?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("HockeyQuant")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(26)
        .frame(width: 420, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func shareRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
