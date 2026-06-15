import SwiftUI

// MARK: - Confetti

/// Performant confetti burst rendered in a single Canvas (native driver).
/// Increment `trigger` to fire a burst. Respects Reduce Motion (renders nothing).
struct ConfettiView: View {
    let trigger: Int
    var duration: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [Piece] = []
    @State private var start = Date()
    @State private var lastTrigger = 0

    private struct Piece: Sendable {
        let x: CGFloat
        let color: Color
        let size: CGFloat
        let delay: Double
        let drift: CGFloat
        let flip: Double
        let sway: Double
    }

    /// Confetti in the favorite team's colors (with white sparkle for pop).
    @MainActor private static var teamPalette: [Color] {
        [Theme.Palette.accent, Theme.Palette.accentAlt, Theme.Palette.cardBorder,
         Theme.Palette.accent, Theme.Palette.accentAlt, .white]
    }

    var body: some View {
        TimelineView(.animation(paused: pieces.isEmpty)) { timeline in
            Canvas { ctx, size in
                guard !pieces.isEmpty else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t <= duration else { return }
                for p in pieces {
                    let lt = t - p.delay
                    guard lt >= 0 else { continue }
                    let prog = lt / (duration - p.delay)
                    guard prog <= 1 else { continue }
                    let y = -20 + (size.height + 60) * CGFloat(prog)
                    let x = p.x * size.width + p.drift * CGFloat(sin(lt * p.sway))
                    let w = max(1, p.size * CGFloat(abs(cos(lt * p.flip))))   // flipping
                    let rect = CGRect(x: x - w / 2, y: y, width: w, height: p.size)
                    ctx.opacity = prog > 0.8 ? (1 - (prog - 0.8) / 0.2) : 1
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, newValue in
            guard !reduceMotion, newValue != lastTrigger else { return }
            lastTrigger = newValue
            start = Date()
            pieces = (0..<110).map { _ in
                Piece(
                    x: .random(in: 0...1),
                    color: Self.teamPalette.randomElement()!,
                    size: .random(in: 6...11),
                    delay: .random(in: 0...0.5),
                    drift: .random(in: 10...45),
                    flip: .random(in: 4...9),
                    sway: .random(in: 2...4)
                )
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration))
                pieces = []
            }
        }
    }
}

// MARK: - Celebration toast

/// A transient celebratory banner (e.g. "+12 XP earned!").
struct CelebrationToast: View {
    let icon: String
    let title: String
    let subtitle: String?
    var tint: Color = Theme.Palette.accent

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.headline())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

// MARK: - Achievement unlock overlay

/// Full-screen celebratory moment when a badge is earned. Tap to dismiss.
struct AchievementUnlockView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(spacing: Theme.Spacing.md) {
                Text("ACHIEVEMENT UNLOCKED")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
                ZStack {
                    Circle().fill(Theme.Palette.accent.opacity(0.18)).frame(width: 120, height: 120)
                    Image(systemName: achievement.icon)
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.Palette.accent)
                }
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -25))
                Text(achievement.name)
                    .font(Theme.Font.title())
                    .foregroundStyle(.white)
                Text(achievement.description)
                    .font(Theme.Font.body())
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Text("Tap to continue")
                    .font(Theme.Font.caption())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.xl)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
        }
    }
}
