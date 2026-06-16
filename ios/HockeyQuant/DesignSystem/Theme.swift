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
        @MainActor static var backgroundStops: [Color] = []
        @MainActor static var backgroundGlow: Double = 0

        // Semantic (adapt to light/dark via asset-free dynamic colors).
        // surface/surfaceRaised/border are overridable so `ThemeStore` can paint
        // cards in the team's secondary color; defaults restore the neutral look.
        static let background = Color(light: 0xF6F7F9, dark: 0x0B0E13)
        static let defaultSurface = Color(light: 0xFFFFFF, dark: 0x151A22)
        static let defaultSurfaceRaised = Color(light: 0xFFFFFF, dark: 0x1C232E)
        static let defaultBorder = Color(light: 0xE6E8EC, dark: 0x262E3A)
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
    @MainActor @ViewBuilder static func backgroundView() -> some View {
        if Palette.backgroundStops.isEmpty {
            Palette.background
        } else {
            AnimatedTeamBackground(colors: Palette.backgroundStops)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                base
                if reduceMotion {
                    blobs(in: geo.size, t: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        blobs(in: geo.size, t: context.date.timeIntervalSinceReferenceDate * speed)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func blobs(in size: CGSize, t: TimeInterval) -> some View {
        let minDim = min(size.width, size.height)
        return ZStack {
            ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                let phase = Double(i) * 1.7
                let sx = 0.24 + Double(i) * 0.045
                let sy = 0.28 + Double(i) * 0.035
                let x = 0.5 + 0.46 * cos(t * sx + phase)
                let y = 0.5 + 0.46 * sin(t * sy + phase * 1.3)
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
