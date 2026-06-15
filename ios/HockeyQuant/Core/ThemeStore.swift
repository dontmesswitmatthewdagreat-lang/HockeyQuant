import SwiftUI
import Observation

/// Drives the app-wide brand theme. By default the app uses the HockeyQuant
/// brand (red accent, blue secondary, neutral background). When a favorite team
/// is set, the app switches to a bold team look: a dark, team-tinted gradient
/// background, the team color as the accent (lightened if it's too dark to read),
/// and a team-derived secondary. The theme follows `auth.favoriteTeam` (synced
/// from `RootView`); `useTeamColors` is a master on/off (default on).
@MainActor
@Observable
final class ThemeStore {
    private let defaults = UserDefaults.standard
    // New key (v2): the original "useTeamColors" defaulted OFF, so existing users
    // had it persisted false. This key defaults ON so team theming follows the
    // favorite team unless explicitly turned off.
    private let useKey = "teamThemeEnabledV2"
    private let teamKey = "themeTeamAbbrev"

    private(set) var accent: Color = Theme.Palette.brandRed
    private(set) var useTeamColors = true
    private(set) var teamAbbrev: String?
    /// True when the bold team theme is active (drives `.preferredColorScheme`).
    private(set) var isTeamTheme = false
    /// Forced color scheme for the active theme (light for light-secondary teams
    /// so dark text reads on the bright cards; dark otherwise). nil = follow system.
    private(set) var forcedScheme: ColorScheme?
    /// Bumped whenever the palette changes. Views read `Theme.Palette.*` statics,
    /// which SwiftUI can't observe, so the app `.id(theme.generation)`s on this to
    /// rebuild and pick up the new colors on a live team change.
    private(set) var generation = 0

    init() {
        useTeamColors = defaults.object(forKey: useKey) as? Bool ?? true
        teamAbbrev = defaults.string(forKey: teamKey)
        apply()
    }

    /// Follow the user's favorite team (called from `RootView` on launch and
    /// whenever the favorite team changes).
    func follow(team: String?) {
        guard team != teamAbbrev else { return }
        teamAbbrev = team
        defaults.set(team, forKey: teamKey)
        apply()
    }

    /// Master on/off for team theming (e.g. a Profile toggle).
    func setTeamColors(enabled: Bool, team: String? = nil) {
        useTeamColors = enabled
        if let team { teamAbbrev = team }
        defaults.set(enabled, forKey: useKey)
        defaults.set(teamAbbrev, forKey: teamKey)
        apply()
    }

    /// Live preview while choosing a team in onboarding (not persisted).
    func preview(team: String?) {
        applyPalette(team: team)
    }

    func resetToBrand() { setTeamColors(enabled: false) }

    private func apply() {
        applyPalette(team: useTeamColors ? teamAbbrev : nil)
        generation += 1   // force the app to rebuild with the new palette
    }

    /// Compute + install the palette for the given team (nil → brand default).
    /// Theme: standard neutral background + white cards outlined in the team's
    /// primary color, with team colors in the accents.
    private func applyPalette(team: String?) {
        // White cards / neutral surfaces; team color lives in the background + accents.
        Theme.Palette.surface = Theme.Palette.defaultSurface
        Theme.Palette.surfaceRaised = Theme.Palette.defaultSurfaceRaised
        Theme.Palette.border = Theme.Palette.defaultBorder

        guard let team, let info = TeamInfo.all[team] else {
            accent = Theme.Palette.brandRed
            Theme.Palette.accent = Theme.Palette.brandRed
            Theme.Palette.accentAlt = Theme.Palette.defaultAccentAlt
            Theme.Palette.cardBorder = Theme.Palette.defaultBorder
            Theme.Palette.backgroundStops = []
            Theme.Palette.backgroundGlow = 0
            forcedScheme = nil
            isTeamTheme = false
            return
        }
        // Accent + card border = the team's PRIMARY (dominant) color;
        // accentAlt = the SECONDARY. Both kept legible on the neutral background.
        let acc = legible(info.primary)
        accent = acc
        Theme.Palette.accent = acc
        Theme.Palette.accentAlt = legible(info.secondary)
        Theme.Palette.cardBorder = acc
        // Standard neutral background (no team gradient); follow the system scheme.
        Theme.Palette.backgroundStops = []
        Theme.Palette.backgroundGlow = 0
        forcedScheme = nil
        isTeamTheme = true
    }

    /// Keep the team color vivid while staying legible on the neutral background.
    /// Scheme-adaptive: on white it only tones down genuinely light colors
    /// (gold/white/silver); on dark it only lifts genuinely dark ones (navy/black).
    /// Saturated mid-tones (red/blue/orange/green) pass through untouched, so
    /// nothing gets washed to a pastel.
    private func legible(_ c: Color) -> Color {
        let l = luminance(c)
        let lightVariant: Color = l > 0.55 ? mix(c, .black, 0.38)
                                : l > 0.42 ? mix(c, .black, 0.18) : c
        let darkVariant: Color  = l < 0.18 ? mix(c, .white, 0.42)
                                : l < 0.32 ? mix(c, .white, 0.18) : c
        return dynamic(light: lightVariant, dark: darkVariant)
    }

    /// A color that resolves differently in light vs dark mode.
    private func dynamic(light: Color, dark: Color) -> Color {
        let l = UIColor(light), d = UIColor(dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    // MARK: - Color math

    private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let (r1, g1, b1) = rgb(a)
        let (r2, g2, b2) = rgb(b)
        return Color(.sRGB,
                     red: r1 * (1 - t) + r2 * t,
                     green: g1 * (1 - t) + g2 * t,
                     blue: b1 * (1 - t) + b2 * t,
                     opacity: 1)
    }

    private func luminance(_ c: Color) -> Double {
        let (r, g, b) = rgb(c)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func rgb(_ c: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
