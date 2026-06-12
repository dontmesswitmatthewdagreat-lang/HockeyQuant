import SwiftUI

// MARK: - Puck

/// A small hockey puck (angled ellipse) used as the writer + bullet dot.
struct PuckDot: View {
    var size: CGFloat = 11
    var body: some View {
        Ellipse()
            .fill(Color.black)
            .overlay(Ellipse().strokeBorder(.white.opacity(0.55), lineWidth: 1))
            .frame(width: size, height: size * 0.62)
            .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
    }
}

// MARK: - PuckRevealText

/// One line of text "written" by a puck: the puck sweeps left→right with a
/// fading trail while a mask reveals the text behind it. Afterwards the puck
/// either returns to the front and settles as the bullet dot, or vanishes
/// (the header hands off to the goal light).
struct PuckRevealText: View {
    let text: String
    var font: Font
    var color: Color
    var settleAsBullet: Bool
    var animated: Bool
    var onComplete: () -> Void = {}

    @State private var progress: CGFloat = 0      // 0…1 sweep
    @State private var settled = false

    private var duration: Double { min(max(Double(text.count) * 0.03, 0.55), 1.5) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if settleAsBullet {
                PuckDot(size: 11)
                    .opacity(settled ? 1 : 0)
                    .scaleEffect(settled ? 1 : 0.3)
                    .padding(.top, 5)
            }
            ZStack(alignment: .topLeading) {
                Text(text).font(font).foregroundStyle(color)
                    .mask(
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width * progress + (progress > 0 ? 14 : 0))
                        }
                    )
                // Sweeping puck + trail (only mid-flight).
                GeometryReader { geo in
                    if progress > 0.01 && progress < 0.99 && !settled {
                        ZStack(alignment: .trailing) {
                            Capsule()
                                .fill(LinearGradient(colors: [.clear, color.opacity(0.5)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: min(geo.size.width * progress, 46), height: 3)
                            PuckDot(size: 12)
                        }
                        .position(x: geo.size.width * progress, y: 11)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .task(id: animated) {
            if !animated {
                progress = 1; settled = true
                return
            }
            progress = 0; settled = false
            withAnimation(.easeInOut(duration: duration)) { progress = 1 }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if settleAsBullet {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { settled = true }
            } else {
                settled = true
            }
            onComplete()
        }
    }
}

// MARK: - Goal light

/// The red goal lamp: a glowing beacon that flashes while `flashing` and settles
/// to a steady glow when done.
struct GoalLightView: View {
    var flashing: Bool
    var size: CGFloat = 18
    @State private var bright = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
                .blur(radius: bright ? 9 : 4)
                .opacity(bright ? 0.9 : 0.35)
                .frame(width: size * 1.7, height: size * 1.7)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), .red],
                                     center: .center, startRadius: 0, endRadius: size / 2))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .frame(width: size, height: size)
                .opacity(bright ? 1 : 0.75)
        }
        .frame(width: size * 1.8, height: size * 1.8)
        .onAppear { updateFlash() }
        .onChange(of: flashing) { _, _ in updateFlash() }
    }

    private func updateFlash() {
        if flashing {
            withAnimation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true)) { bright = true }
        } else {
            withAnimation(.easeOut(duration: 0.5)) { bright = false }
        }
    }
}

// MARK: - RAPID DIGEST card

/// The animated key-points card: a puck writes the "RAPID DIGEST" header, then
/// turns into a flashing goal light while each bullet is written by its own
/// puck (which settles back at the front as the bullet dot). Plays once per
/// digest (tap the header to replay); Reduce Motion gets a plain fade.
struct RapidDigestCard: View {
    let points: [String]
    let digestId: String
    let asOf: String?

    @AppStorage("rapidDigestSeenIds") private var seenIds = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerDone = false
    @State private var revealed = 0          // bullets fully triggered
    @State private var flashing = false
    @State private var animating = false
    @State private var runID = 0             // bump to replay

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    PuckRevealText(text: "RAPID DIGEST",
                                   font: .system(size: 15, weight: .black, design: .rounded),
                                   color: Theme.Palette.accent,
                                   settleAsBullet: false,
                                   animated: animating,
                                   onComplete: headerFinished)
                        .id("hdr-\(runID)")
                    GoalLightView(flashing: flashing, size: 15)
                        .opacity(headerDone ? 1 : 0)
                        .scaleEffect(headerDone ? 1 : 0.2)
                    Spacer()
                    if let asOf {
                        Text("as of \(asOf)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { replay() }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        if i < revealed {
                            PuckRevealText(text: p,
                                           font: Theme.Font.body(),
                                           color: Theme.Palette.textPrimary,
                                           settleAsBullet: true,
                                           animated: animating,
                                           onComplete: { bulletFinished(i) })
                                .id("kp-\(i)-\(runID)")
                        }
                    }
                }
            }
        }
        .onAppear { start() }
    }

    // MARK: orchestration

    private var alreadySeen: Bool { seenIds.split(separator: ",").map(String.init).contains(digestId) }

    private func start() {
        if reduceMotion || alreadySeen {
            animating = false
            headerDone = true
            flashing = false
            revealed = points.count
        } else {
            runAnimated()
        }
    }

    private func replay() {
        guard !animating || revealed == points.count else { return }
        runID += 1
        runAnimated()
    }

    private func runAnimated() {
        animating = true
        headerDone = false
        flashing = false
        revealed = 0
    }

    private func headerFinished() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { headerDone = true }
        flashing = true
        withAnimation(.easeOut(duration: 0.25)) { revealed = 1 }
    }

    private func bulletFinished(_ i: Int) {
        if i + 1 < points.count {
            withAnimation(.easeOut(duration: 0.25)) { revealed = i + 2 }
        } else {
            flashing = false
            markSeen()
        }
    }

    private func markSeen() {
        var ids = seenIds.split(separator: ",").map(String.init)
        if !ids.contains(digestId) {
            ids.append(digestId)
            seenIds = ids.suffix(20).joined(separator: ",")
        }
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
