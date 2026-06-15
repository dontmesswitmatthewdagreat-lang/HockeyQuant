import SwiftUI

// MARK: - Card

/// Standard surface container used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.Palette.surface)
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

    @State private var pressed = false

    var body: some View {
        label()
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                action()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
            // Expose as a real button for VoiceOver + UI testing.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
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

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Font.statNumber())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
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
