import SwiftUI

// MARK: - Card team-blobs (opt-in, per subtree)

/// When true, `Card` drifts soft team-SECONDARY blobs inside its surface so the
/// white boxes carry motion + color. Set via `.environment(\.cardTeamBlobs, true)`
/// on a subtree (the Play tab); off everywhere else, so News etc. are unchanged.
private struct CardTeamBlobsKey: EnvironmentKey { static let defaultValue = false }
private struct CardSurfaceKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues {
    var cardTeamBlobs: Bool {
        get { self[CardTeamBlobsKey.self] }
        set { self[CardTeamBlobsKey.self] = newValue }
    }
    /// Overrides a `Card`'s fill color (e.g. the Fantasy section paints cards yellow).
    var cardSurfaceOverride: Color? {
        get { self[CardSurfaceKey.self] }
        set { self[CardSurfaceKey.self] = newValue }
    }
}

// MARK: - Card

/// Standard surface container used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: () -> Content
    @Environment(\.cardTeamBlobs) private var teamBlobs
    @Environment(\.cardSurfaceOverride) private var surfaceOverride
    // Stable per-card phase so each card's blobs drift independently of its neighbors.
    @State private var blobSeed = Double.random(in: 0..<1000)

    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack {
                    surfaceOverride ?? Theme.Palette.surface
                    if teamBlobs, !Theme.Palette.cardBlobStops.isEmpty {
                        AnimatedTeamBackground(colors: Theme.Palette.cardBlobStops,
                                               base: .clear, radiusFactor: 1.0, speed: 2.4, fps: 24,
                                               spread: true, seed: blobSeed)
                            .opacity(0.8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Palette.cardBorder, lineWidth: 1.5)
            )
    }
}

// MARK: - Pressable button (press-scale + haptic)

/// Tactile button wrapper: scales on press and fires a light haptic.
/// Native feel for primary CTAs and pick controls.
struct PressableButton<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        // A real Button with a press-scaling style. The earlier hand-rolled
        // `DragGesture(minimumDistance: 0)` captured every touch-drag that began on
        // the button, which blocked the enclosing ScrollView from scrolling whenever
        // a swipe started on a card. A ButtonStyle scales on press AND correctly
        // yields the drag to the ScrollView.
        Button {
            Haptics.tap()
            action()
        } label: {
            label()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(.isButton)
    }
}

/// Scales the label down slightly while pressed, without intercepting scroll drags.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Confidence chip

struct ConfidenceChip: View {
    let confidence: String

    private var color: Color {
        switch confidence.uppercased() {
        case "STRONG": return Theme.Palette.strong
        case "MODERATE": return Theme.Palette.moderate
        default: return Theme.Palette.close
        }
    }

    var body: some View {
        Text(confidence.capitalized)
            .font(Theme.Font.caption())
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

// MARK: - Win probability bar

/// Two-sided bar showing away vs home win probability.
struct WinProbBar: View {
    let awayProb: Double   // 0-100
    let homeProb: Double   // 0-100
    let awayColor: Color
    let homeColor: Color

    private var awayFraction: CGFloat {
        let total = awayProb + homeProb
        guard total > 0 else { return 0.5 }
        return CGFloat(awayProb / total)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                awayColor
                    .frame(width: max(0, geo.size.width * awayFraction))
                homeColor
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

// MARK: - Stat pill

struct StatPill: View {
    let label: String
    let value: String
    var labelColor: Color = Theme.Palette.textSecondary   // overridable (Play header uses black)

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Font.statNumber())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Loading shimmer

struct LoadingShimmer: View {
    var height: CGFloat = 120
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .fill(Theme.Palette.surface)
            .frame(height: height)
            .overlay(
                LinearGradient(
                    colors: [.clear, Theme.Palette.border.opacity(0.6), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .offset(x: phase * 250)
                .mask(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

// MARK: - Empty / error states

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Palette.accent.opacity(0.85))
            Text(title)
                .font(Theme.Font.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
    }
}

/// Surfaces an error to the user instead of swallowing it. Includes retry.
struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Palette.moderate)
            Text("Something went wrong")
                .font(Theme.Font.headline())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                PressableButton(action: retry) {
                    Text("Try again")
                        .font(Theme.Font.headline())
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Palette.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func tap() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }

    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }
}

// MARK: - Cap money formatting

extension Int {
    /// A Cap Space dollar amount shown in millions, e.g. 12_275_000 → "$12.3M".
    var asCapMoney: String { String(format: "$%.1fM", Double(self) / 1_000_000) }
}
