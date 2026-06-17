import SwiftUI

/// Single source of truth for HockeyQuant's visual language.
/// Tokens first, screens second (design-system-first).
enum Theme {

    // MARK: - Color tokens

    enum Palette {
        /// HockeyQuant brand red. Mutable so `ThemeStore` can swap it for a
        /// favorite-team color app-wide. Every `Theme.Palette.accent` read picks
        /// up the current value at render time. (Main-actor: UI only.)
        @MainActor static var accent = Color(hex: 0xD7263D)
        /// The fixed brand red, regardless of any team-color override.
        static let brandRed = Color(hex: 0xD7263D)
        /// Secondary brand color (HockeyQuant blue). `ThemeStore` swaps in a
        /// team-tinted secondary when a favorite team is themed.
        static let defaultAccentAlt = Color(hex: 0x0A84FF)
        @MainActor static var accentAlt = defaultAccentAlt

        /// App background gradient stops + corner glow, driven by `ThemeStore`.
        /// Empty stops → the flat neutral background (the default, no-team look).
        /// `backgroundStops` mixes the team's primary + secondary (News + default).
        @MainActor static var backgroundStops: [Color] = []
        @MainActor static var backgroundGlow: Double = 0

        /// Play-tab split: the background uses ONLY the team's PRIMARY color
        /// (`backgroundStopsPrimary`), while the team's SECONDARY color drifts as
        /// soft blobs *inside* the white cards (`cardBlobStops`). Empty = no team.
        @MainActor static var backgroundStopsPrimary: [Color] = []
        @MainActor static var cardBlobStops: [Color] = []

        // Semantic (adapt to light/dark via asset-free dynamic colors).
        // surface/surfaceRaised/border are overridable so `ThemeStore` can paint
        // cards in the team's secondary color; defaults restore the neutral look.
        static let background = Color(light: 0xF6F7F9, dark: 0x0B0E13)
        static let defaultSurface = Color(light: 0xFFFFFF, dark: 0x151A22)
        static let defaultSurfaceRaised = Color(light: 0xFFFFFF, dark: 0x1C232E)
        static let defaultBorder = Color(light: 0xE6E8EC, dark: 0x262E3A)
        /// Fantasy-section card fill — a deep marigold yellow-orange so the Fantasy
        /// screens read as a distinct "game within the app" (via `.environment(\.cardSurfaceOverride, …)`).
        static let fantasySurface = Color(light: 0xFFC24C, dark: 0x3A2B10)
        @MainActor static var surface = defaultSurface
        @MainActor static var surfaceRaised = defaultSurfaceRaised
        @MainActor static var border = defaultBorder
        /// Card outline — `ThemeStore` tints this with the team's primary color
        /// (the rest of the UI keeps the neutral `border`).
        @MainActor static var cardBorder = defaultBorder

        static let textPrimary = Color(light: 0x10141B, dark: 0xF2F5F8)
        static let textSecondary = Color(light: 0x5A6472, dark: 0x9AA6B4)
        static let textTertiary = Color(light: 0x8A93A1, dark: 0x6B7686)

        // Confidence / status
        static let strong = Color(hex: 0x14CA64)
        static let moderate = Color(hex: 0xF5A623)
        static let close = Color(hex: 0x8A93A1)

        static let positive = Color(hex: 0x14CA64)
        static let negative = Color(hex: 0xE5484D)
        static let live = Color(hex: 0xE5484D)
    }

    // MARK: - Background

    /// The app-wide background. Flat neutral by default; when a favorite team is
    /// themed, a slowly-drifting team-colored gradient (`backgroundStops`). Use
    /// in a screen's root `ZStack` in place of `Palette.background.ignoresSafeArea()`.
    /// Pass `stops:` to override (e.g. the Play tab uses `backgroundStopsPrimary`
    /// for a primary-only wash); defaults to the mixed `backgroundStops`.
    @MainActor @ViewBuilder static func backgroundView(stops: [Color]? = nil) -> some View {
        let resolved = stops ?? Palette.backgroundStops
        if resolved.isEmpty {
            Palette.background
        } else {
            AnimatedTeamBackground(colors: resolved)
        }
    }

    // MARK: - Spacing scale (4pt base)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radii

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Typography ramp

    enum Font {
        static func display() -> SwiftUI.Font { .system(size: 34, weight: .heavy, design: .rounded) }
        static func title() -> SwiftUI.Font { .system(size: 22, weight: .bold, design: .rounded) }
        static func headline() -> SwiftUI.Font { .system(size: 17, weight: .semibold, design: .rounded) }
        static func headlineHeavy() -> SwiftUI.Font { .system(size: 17, weight: .heavy, design: .rounded) }
        static func body() -> SwiftUI.Font { .system(size: 15, weight: .regular) }
        static func caption() -> SwiftUI.Font { .system(size: 13, weight: .medium) }
        static func mono() -> SwiftUI.Font { .system(size: 15, weight: .semibold, design: .monospaced) }
        static func statNumber() -> SwiftUI.Font { .system(size: 20, weight: .bold, design: .rounded) }
    }
}

// MARK: - Animated team background

/// Soft, slowly-drifting team-colored "blobs" (aurora/mesh style): a few large
/// radial gradients in light team tints float around over a white base, so the
/// white cards + dark text stay readable on top. Respects Reduce Motion (still).
struct AnimatedTeamBackground: View {
    var colors: [Color]
    var base: Color = .white
    var radiusFactor: CGFloat = 0.66
    var speed: Double = 1
    var fps: Double = 30           // lower for the many small in-card instances
    var spread: Bool = false       // anchor blobs in separate regions so they don't bunch (in-card use)
    var seed: Double = 0           // phase offset so sibling instances (e.g. cards) animate independently
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                base
                if reduceMotion {
                    blobs(in: geo.size, t0: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / fps)) { context in
                        blobs(in: geo.size, t0: context.date.timeIntervalSinceReferenceDate * speed)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func blobs(in size: CGSize, t0: TimeInterval) -> some View {
        let minDim = min(size.width, size.height)
        let n = max(1.0, Double(colors.count))
        let t = t0 + seed                 // per-instance offset → independent motion
        return ZStack {
            ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                let phase = Double(i) * 1.7
                let sx = 0.24 + Double(i) * 0.045
                let sy = 0.28 + Double(i) * 0.035
                // Default: all blobs orbit the center (full-screen washes). `spread`:
                // anchor each blob in its own band (across the width, alternating
                // top/bottom) with a wider local drift, so in-card blobs stay apart.
                let cx = spread ? (Double(i) + 0.5) / n : 0.5
                let cy = spread ? (i % 2 == 0 ? 0.32 : 0.68) : 0.5
                let amp = spread ? 0.26 : 0.46
                let x = cx + amp * cos(t * sx + phase)
                let y = cy + amp * sin(t * sy + phase * 1.3)
                let r = minDim * (radiusFactor + 0.12 * sin(t * 0.14 + phase))
                Circle()
                    .fill(RadialGradient(colors: [c, c.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: r))
                    .frame(width: r * 2, height: r * 2)
                    .position(x: x * size.width, y: y * size.height)
            }
        }
    }
}

extension AnimatedTeamBackground {
    /// Luminance (0 = black … 1 = white) of the default centered-orbit blob field
    /// at screen point `p` and time `t`, composited over a white base. Lets text
    /// overlaid on the background flip black↔white to stay readable as blobs drift
    /// beneath it. Mirrors the non-`spread` blob math + `backgroundView` defaults.
    static func backgroundLuminance(colors: [Color], at p: CGPoint, in size: CGSize,
                                    t: TimeInterval, radiusFactor: CGFloat = 0.66) -> Double {
        guard size.width > 0, size.height > 0, !colors.isEmpty else { return 1 }
        let minDim = Double(min(size.width, size.height))
        var rr = 1.0, gg = 1.0, bb = 1.0    // white base
        for (i, c) in colors.enumerated() {
            let phase = Double(i) * 1.7
            let sx = 0.24 + Double(i) * 0.045
            let sy = 0.28 + Double(i) * 0.035
            let cx = (0.5 + 0.46 * cos(t * sx + phase)) * Double(size.width)
            let cy = (0.5 + 0.46 * sin(t * sy + phase * 1.3)) * Double(size.height)
            let rad = minDim * (Double(radiusFactor) + 0.12 * sin(t * 0.14 + phase))
            guard rad > 0 else { continue }
            let a = max(0, 1 - hypot(Double(p.x) - cx, Double(p.y) - cy) / rad)   // linear radial falloff
            if a <= 0 { continue }
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            UIColor(c).getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            rr = rr * (1 - a) + Double(cr) * a
            gg = gg * (1 - a) + Double(cg) * a
            bb = bb * (1 - a) + Double(cb) * a
        }
        return 0.2126 * rr + 0.7152 * gg + 0.0722 * bb
    }
}

// MARK: - Color helpers

extension Color {
    /// Hex int initializer, e.g. `Color(hex: 0x14CA64)`.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Dynamic color that resolves differently in light vs dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}
