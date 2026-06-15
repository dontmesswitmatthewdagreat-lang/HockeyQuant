import SwiftUI

// MARK: - Puck

/// A crisp hockey puck (SF Symbol — `hockey.puck.fill`) used as the bullet dot.
struct PuckDot: View {
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: "hockey.puck.fill")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(
                LinearGradient(colors: [Color(white: 0.22), .black],
                               startPoint: .top, endPoint: .bottom))
            .overlay(
                Image(systemName: "hockey.puck.fill")
                    .font(.system(size: size, weight: .black))
                    .foregroundStyle(.white.opacity(0.25))
                    .mask(LinearGradient(colors: [.white, .clear],
                                         startPoint: .top, endPoint: .center))
            )
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
    }
}

// MARK: - Goal light

/// The NHL goal lamp (custom `GoalLight` asset) that pulses red while `flashing`,
/// as if the light is going off after a goal. Sizes by height; the cage + beams
/// keep their natural 2:1 aspect.
struct GoalLightIcon: View {
    var height: CGFloat = 22
    var flashing: Bool = true
    @State private var bright = false

    var body: some View {
        Image("GoalLight")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .brightness(bright ? 0.06 : -0.12)
            .opacity(bright ? 1.0 : 0.62)
            .shadow(color: .red.opacity(bright ? 0.75 : 0.15),
                    radius: bright ? 6 : 2)
            .onAppear { updateFlash() }
            .onChange(of: flashing) { _, _ in updateFlash() }
    }

    private func updateFlash() {
        if flashing {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                bright = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.4)) { bright = false }
        }
    }
}

// MARK: - RAPID DIGEST card

/// The key-points card: a "RAPID DIGEST" header (same face as the News/Prospects
/// tabs) beside a flashing goal light, then puck-bulleted key points that fade up
/// one after another (the same staggered entrance the Prospects grid uses).
struct RapidDigestCard: View {
    let points: [String]
    let digestId: String
    let asOf: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("RAPID DIGEST")
                            .font(.system(size: 21, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.accent)
                            .lineLimit(1)
                        GoalLightIcon(height: 22)
                        Spacer(minLength: 0)
                    }
                    if let asOf {
                        Text("as of \(asOf)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            PuckDot(size: 13)
                            Text(p)
                                .font(Theme.Font.body())
                                .foregroundStyle(Theme.Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .staggeredEntrance(index: i)
                    }
                }
            }
        }
        .id(digestId)   // a fresh digest replays the staggered entrance
    }
}

// MARK: - Animated gradient ring (story CTA)

/// A rotating, hue-blending gradient ring border for "you have unwatched
/// stories"; fades away once the digest has been watched.
struct AnimatedGradientRing: View {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 2.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 40).truncatingRemainder(dividingBy: 360))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt,
                                             Color(red: 0.9, green: 0.3, blue: 0.5),
                                             Theme.Palette.accentAlt, Theme.Palette.accent],
                                    center: .center, angle: angle),
                    lineWidth: lineWidth)
        }
    }
}
