import SwiftUI

// Components for the redesigned "arcade mode-select" Play home. Each segment is a
// distinct gamified tile; data all comes pre-loaded from GamificationStore.

// MARK: - Section label

/// A small-caps segment header with a short accent tick and an optional trailing accessory.
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.textPrimary)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.Palette.accent)
                .frame(width: 16, height: 3)
            Spacer(minLength: Theme.Spacing.xs)
            trailing()
        }
        .padding(.horizontal, 2)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title, trailing: { EmptyView() }) }
}

/// A compact pill chip used for the season tag and the slate "called" progress.
struct PillChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Theme.Palette.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - Identity HUD (GM tier / XP / streak)

/// The player's account identity: GM tier, XP progress, and current streak. Taps → SeasonView.
struct GMIdentityCard: View {
    let stats: UserStats
    let season: SeasonStats

    private var tier: GMTier { GMTier.current(forXp: season.xp) }
    private var next: GMTier? { GMTier.next(forXp: season.xp) }
    private var progress: Double { GMTier.progress(forXp: season.xp) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(tier.color.opacity(0.18))
                        Circle().stroke(tier.color.opacity(0.55), lineWidth: 2)
                        Image(systemName: tier.icon).font(.system(size: 24)).foregroundStyle(tier.color)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tier.name).font(Theme.Font.title()).foregroundStyle(Theme.Palette.textPrimary)
                        Text("General Manager").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    streakChip
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }

                // XP position on the tier ladder → the signature range gauge.
                RangeGauge(fraction: next == nil ? 1 : progress,
                           hiLabel: next.map { "\(season.xp) / \($0.threshold) XP → \($0.name)" }
                                    ?? "Max tier · \(season.xp) XP",
                           tint: tier.color, filled: true)

                Divider().overlay(Theme.Palette.border)

                // Season metric strip — a compact stats panel.
                HStack(spacing: Theme.Spacing.sm) {
                    metric("Record", "\(stats.picksCorrect)–\(max(0, stats.picksMade - stats.picksCorrect))")
                    metricDivider
                    metric("Accuracy", stats.picksMade > 0 ? "\(Int(stats.accuracy.rounded()))%" : "—")
                    metricDivider
                    metric("Beat AI", "\(stats.beatsModel)")
                    metricDivider
                    metric("Cups", "\(stats.stanleyCups)")
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary).contentTransition(.numericText())
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Divider().frame(height: 26).overlay(Theme.Palette.border)
    }

    private var streakChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xFF6B35))
            Text("\(stats.currentStreak)").font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text("· best \(stats.bestStreak)").font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(hex: 0xFF6B35).opacity(0.12)).clipShape(Capsule())
    }
}

// MARK: - Featured ranked mode (Global League)

/// The marquee "ranked" mode: a glowing tile with the Stanley Cup ring, arena tier,
/// and Cap Space / Accuracy / Picks. Taps → GlobalLeagueView.
struct RankedModeTile: View {
    let stats: UserStats

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: Double = 0
    @State private var displayCups: Int = 0

    private var arena: Arena { Arena.current(forCups: stats.stanleyCups) }

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.md) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    cupRing
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("GLOBAL LEAGUE")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.Palette.textPrimary)
                            rankedPill
                        }
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(arena.name)
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(arena.color)
                            accuracyVerdict
                        }
                        Text("Climb the Cup ladder vs everyone")
                            .font(.system(size: 11)).foregroundStyle(Theme.Palette.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Divider().overlay(Theme.Palette.border)
                statsRow
            }
        }
        .overlay(
            AnimatedGradientRing(cornerRadius: Theme.Radius.md, lineWidth: 2)
                .opacity(reduceMotion ? 0.6 : 1)
                .allowsHitTesting(false)
        )
        .onAppear { animateIn() }
        .onChange(of: stats.stanleyCups) { _, _ in animateIn() }
    }

    private func animateIn() {
        let target = Arena.progress(forCups: stats.stanleyCups)
        guard !reduceMotion else { ring = target; displayCups = stats.stanleyCups; return }
        withAnimation(.easeOut(duration: 0.9)) { ring = target; displayCups = stats.stanleyCups }
    }

    /// A short "how are your picks going" verdict on Global League accuracy.
    private var accuracyVerdict: AnyView {
        guard stats.picksMade > 0 else { return AnyView(StatusPill(text: "Unranked", color: Theme.Palette.textTertiary)) }
        let acc = stats.accuracy
        if acc >= 55 { return AnyView(StatusPill(text: "Sharp", systemImage: "flame.fill", color: Theme.Palette.positive, solid: true)) }
        if acc >= 50 { return AnyView(StatusPill(text: "Solid", color: Theme.Palette.positive)) }
        if acc >= 45 { return AnyView(StatusPill(text: "Steady", color: Theme.Palette.moderate)) }
        return AnyView(StatusPill(text: "Cold", color: Theme.Palette.negative))
    }

    private var rankedPill: some View {
        Text("RANKED")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.Palette.accent).clipShape(Capsule())
    }

    private var cupRing: some View {
        ZStack {
            Circle().stroke(Theme.Palette.border, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, ring))
                .stroke(AngularGradient(colors: [arena.color, Theme.Palette.accent, arena.color], center: .center),
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
    }

    private var statsRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatPill(label: "Cap Space", value: stats.capSpace.asCapMoney, labelColor: Theme.Palette.textPrimary)
            Divider().frame(height: 28).overlay(Theme.Palette.border)
            StatPill(label: "Accuracy", value: stats.picksMade > 0 ? "\(Int(stats.accuracy.rounded()))%" : "—", labelColor: Theme.Palette.textPrimary)
            Divider().frame(height: 28).overlay(Theme.Palette.border)
            StatPill(label: "Picks", value: "\(stats.picksMade)", labelColor: Theme.Palette.textPrimary)
        }
    }
}

// MARK: - Secondary mode tile (Private Leagues / My Franchise)

/// A square-ish gamified mode tile used 2-up under the ranked hero.
struct ModeTile: View {
    let title: String
    let icon: String
    let subtitle: String
    let tint: Color

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(tint.opacity(0.16))
                    Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.headlineHeavy()).foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                }
                HStack(spacing: 3) {
                    Text("ENTER").font(.system(size: 10, weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
