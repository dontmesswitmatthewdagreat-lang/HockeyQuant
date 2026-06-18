import SwiftUI

// MARK: - Level / streak / stats header

struct PlayHeaderCard: View {
    let stats: UserStats

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: Double = 0
    @State private var displayCups: Int = 0

    private var arena: Arena { Arena.current(forCups: stats.stanleyCups) }

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                HStack(alignment: .top) {
                    cupRing
                    Spacer()
                    streakBadge
                }
                Divider().overlay(Theme.Palette.border)
                statsRow
            }
        }
        .onAppear { animateIn() }
        .onChange(of: stats.stanleyCups) { _, _ in animateIn() }
    }

    private func animateIn() {
        let target = Arena.progress(forCups: stats.stanleyCups)
        guard !reduceMotion else {
            ring = target
            displayCups = stats.stanleyCups
            return
        }
        withAnimation(.easeOut(duration: 0.9)) {
            ring = target
            displayCups = stats.stanleyCups
        }
    }

    // Stanley Cup count + arena progress (replaces the old XP/level ring).
    private var cupRing: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Theme.Palette.border, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.02, ring))
                    .stroke(
                        AngularGradient(
                            colors: [arena.color, Theme.Palette.accent, arena.color],
                            center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(arena.color)
                    Text("\(displayCups)").font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                    Text("CUPS").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            .frame(width: 72, height: 72)
            Text(arena.name)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(arena.color)
        }
    }

    private var streakBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(stats.currentStreak)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text("current streak")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("best \(stats.bestStreak)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatPill(label: "Cap Space", value: capText, labelColor: Theme.Palette.textPrimary)
            Divider().frame(height: 28).overlay(Theme.Palette.border)
            StatPill(label: "Accuracy", value: stats.picksMade > 0 ? "\(Int(stats.accuracy.rounded()))%" : "—", labelColor: Theme.Palette.textPrimary)
            Divider().frame(height: 28).overlay(Theme.Palette.border)
            StatPill(label: "Picks", value: "\(stats.picksMade)", labelColor: Theme.Palette.textPrimary)
        }
    }

    private var capText: String { stats.capSpace.asCapMoney }
}

// MARK: - Season banner (entry to the meta-game)

struct SeasonBanner: View {
    let stats: SeasonStats

    private var tier: GMTier { GMTier.current(forXp: stats.xp) }
    private var nextTier: GMTier? { GMTier.next(forXp: stats.xp) }
    private var progress: Double { GMTier.progress(forXp: stats.xp) }

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle().fill(tier.color.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: tier.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(tier.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(tier.name)
                            .font(Theme.Font.headlineHeavy())
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Text(Season.current.id)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Palette.background)
                            Capsule().fill(tier.color)
                                .frame(width: geo.size.width * CGFloat(progress))
                        }
                    }
                    .frame(height: 5)
                    Text(nextTier.map { "\(stats.xp)/\($0.threshold) XP → \($0.name)" } ?? "Top tier · \(stats.xp) XP")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }
}

// MARK: - Call-the-game card

struct CallGameCard: View {
    let game: GamePrediction
    let pick: UserPick?
    let isSubmitting: Bool
    let onPick: (String) -> Void

    private var graded: Bool { pick?.correct != nil }

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                header
                HStack(spacing: Theme.Spacing.sm) {
                    teamButton(game.away)
                    VStack(spacing: 2) {
                        Text("@").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textPrimary)
                    }
                    .frame(width: 28)
                    teamButton(game.home)
                }
                if graded { resultBanner }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Model: \(game.pick)")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            if isSubmitting {
                ProgressView()
            } else if pick == nil {
                Text("TAP TO CALL IT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
            } else if !graded {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("PICKED")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Palette.strong)
            }
        }
    }

    private func teamButton(_ team: TeamAnalysis) -> some View {
        let info = team.info
        let isUserPick = pick?.pick.uppercased() == team.team.uppercased()
        let isModelPick = game.pick.uppercased() == team.team.uppercased()
        let isWinnerWhenGraded = graded && isUserPick && (pick?.correct == true)
        let isLoserWhenGraded = graded && isUserPick && (pick?.correct == false)

        return PressableButton(action: { if !graded { onPick(team.team) } }) {
            VStack(spacing: Theme.Spacing.xs) {
                CrestView(abbrev: team.team, size: 48)
                    .saturation(isUserPick || !graded ? 1 : 0.6)
                    .overlay(Circle().stroke(Theme.Palette.accent, lineWidth: isUserPick ? 3 : 0))
                    .scaleEffect(isUserPick ? 1.08 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isUserPick)
                Text(info.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if isModelPick {
                    Text("MODEL").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isUserPick ? info.color.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(borderColor(isUserPick: isUserPick, win: isWinnerWhenGraded, lose: isLoserWhenGraded),
                            lineWidth: isUserPick ? 2 : 1)
            )
        }
        .disabled(graded)
    }

    private func borderColor(isUserPick: Bool, win: Bool, lose: Bool) -> Color {
        if win { return Theme.Palette.positive }
        if lose { return Theme.Palette.negative }
        if isUserPick { return Theme.Palette.accent }
        return Theme.Palette.border
    }

    private var resultBanner: some View {
        let correct = pick?.correct == true
        return HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: correct ? "checkmark.seal.fill" : "xmark.seal.fill")
            Text(correct ? "Correct!" : "Missed")
                .font(Theme.Font.caption())
            Spacer()
            Text("+\(pick?.xpAwarded ?? 0) XP")
                .font(Theme.Font.caption())
        }
        .foregroundStyle(correct ? Theme.Palette.positive : Theme.Palette.negative)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background((correct ? Theme.Palette.positive : Theme.Palette.negative).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }
}

// MARK: - Adaptive title

/// A large title whose color flips black↔white to stay readable as the team
/// background blobs drift beneath it. Samples the blob luminance under the title
/// each frame and crossfades through a steep, narrow band (a quick gradient, with
/// almost no time spent in the hard-to-read gray middle).
struct AdaptiveBlobTitle: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGRect = .zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { ctx in
            let stops = Theme.Palette.backgroundStopsPrimary
            Text(text)
                .font(Theme.Font.display())
                .foregroundStyle(Self.color(stops: stops, frame: frame,
                                            screen: UIScreen.main.bounds.size,
                                            t: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { frame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in frame = f }
            }
        )
        .accessibilityAddTraits(.isHeader)
    }

    /// Black on light background, white on dark — with a steep smoothstep so the
    /// transition is fast and barely passes through gray.
    private static func color(stops: [Color], frame: CGRect, screen: CGSize, t: TimeInterval) -> Color {
        guard !stops.isEmpty, frame != .zero else { return Theme.Palette.textPrimary }
        let lum = AnimatedTeamBackground.backgroundLuminance(
            colors: stops, at: CGPoint(x: frame.midX, y: frame.midY), in: screen, t: t)
        let u = max(0, min(1, (lum - 0.57) / (0.65 - 0.57)))   // narrow band → quick flip
        let s = u * u * (3 - 2 * u)                            // dark→0 (white text), light→1 (black)
        return Color(white: 1 - s)
    }
}
