import SwiftUI

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
