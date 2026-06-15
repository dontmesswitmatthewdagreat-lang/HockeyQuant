import SwiftUI

/// Lightweight team metadata keyed by NHL abbreviation.
/// v1 deliberately uses abbreviations + team color tokens instead of official
/// logos to avoid trademark/IP exposure (see plan §D / Data-Rights map).
/// Colors are the official primary + secondary (accent) brand hexes.
struct TeamInfo: Sendable {
    let abbrev: String
    let name: String
    let primaryHex: UInt32
    let secondaryHex: UInt32

    var primary: Color { Color(hex: primaryHex) }
    var secondary: Color { Color(hex: secondaryHex) }

    /// A single vivid, recognizable color for charts / win bars / shot maps:
    /// the primary, unless it's effectively black/white/grey — then the
    /// secondary (so e.g. the Bruins read as gold, not black).
    var color: Color { Color(hex: colorHex) }

    /// Hex of the vivid `color` — for callers that need the raw value (e.g. the
    /// widget's contrast helper).
    var colorHex: UInt32 {
        (Self.isDull(primaryHex) && !Self.isDull(secondaryHex)) ? secondaryHex : primaryHex
    }

    /// Monogram color for the crest disc (filled with `primary`): the secondary
    /// when it contrasts with the primary, otherwise white/near-black by the
    /// primary's brightness (handles same-color teams like a black-on-black).
    var crestMonogram: Color {
        if abs(Self.lum(primaryHex) - Self.lum(secondaryHex)) >= 0.28 { return secondary }
        return Self.lum(primaryHex) < 0.5 ? .white : Color(hex: 0x10141B)
    }

    static func lookup(_ abbrev: String) -> TeamInfo {
        all[abbrev.uppercased()] ?? TeamInfo(abbrev: abbrev, name: abbrev,
                                             primaryHex: 0x5A6472, secondaryHex: 0x8A93A1)
    }

    static let all: [String: TeamInfo] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.abbrev, $0) }
    )

    // MARK: - Color math (operates on hex so it's cheap + Sendable)

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
    static func lum(_ hex: UInt32) -> Double {
        let (r, g, b) = rgb(hex); return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    private static func sat(_ hex: UInt32) -> Double {
        let (r, g, b) = rgb(hex); let mx = max(r, g, b), mn = min(r, g, b)
        return mx <= 0 ? 0 : (mx - mn) / mx
    }
    /// "Dull" = effectively greyscale and very dark or very light (black/white/grey).
    private static func isDull(_ hex: UInt32) -> Bool {
        let l = lum(hex); return sat(hex) < 0.25 && (l < 0.16 || l > 0.85)
    }

    // MARK: - Official primary + secondary (2026-27)

    // primary = the team's dominant/recognizable color; secondary = its complement.
    private static let table: [TeamInfo] = [
        // Liked reference profiles (kept): PHI CAR CHI COL CBJ DET EDM FLA NJD NYI NYR SJS VAN VGK WSH.
        // Others: primary brightened to match the closest liked team's hue.
        TeamInfo(abbrev: "ANA", name: "Anaheim Ducks",          primaryHex: 0xF74902, secondaryHex: 0xB9975B), // orange / gold
        TeamInfo(abbrev: "BOS", name: "Boston Bruins",          primaryHex: 0x000000, secondaryHex: 0xFFB81C), // black / gold
        TeamInfo(abbrev: "BUF", name: "Buffalo Sabres",         primaryHex: 0x003E98, secondaryHex: 0xFFB81C), // bright blue / gold
        TeamInfo(abbrev: "CGY", name: "Calgary Flames",         primaryHex: 0xC8102E, secondaryHex: 0xF1BE48), // red / gold
        TeamInfo(abbrev: "CAR", name: "Carolina Hurricanes",    primaryHex: 0xCC0000, secondaryHex: 0x111111), // red / black
        TeamInfo(abbrev: "CHI", name: "Chicago Blackhawks",     primaryHex: 0xCF0A2C, secondaryHex: 0x000000), // red / black
        TeamInfo(abbrev: "COL", name: "Colorado Avalanche",     primaryHex: 0x6F263D, secondaryHex: 0x236192), // burgundy / blue
        TeamInfo(abbrev: "CBJ", name: "Columbus Blue Jackets",  primaryHex: 0x002654, secondaryHex: 0xCE1126), // navy / red
        TeamInfo(abbrev: "DAL", name: "Dallas Stars",           primaryHex: 0x00843D, secondaryHex: 0x8F8F8C), // bright green / silver
        TeamInfo(abbrev: "DET", name: "Detroit Red Wings",      primaryHex: 0xCE1126, secondaryHex: 0xFFFFFF), // red / white
        TeamInfo(abbrev: "EDM", name: "Edmonton Oilers",        primaryHex: 0x00205B, secondaryHex: 0xFC4C02), // navy / orange
        TeamInfo(abbrev: "FLA", name: "Florida Panthers",       primaryHex: 0xC8102E, secondaryHex: 0x041E42), // red / navy
        TeamInfo(abbrev: "LAK", name: "Los Angeles Kings",      primaryHex: 0x000000, secondaryHex: 0xA2AAAD), // black / silver
        TeamInfo(abbrev: "MIN", name: "Minnesota Wild",         primaryHex: 0x156F3C, secondaryHex: 0xDDCBA4), // bright green / wheat
        TeamInfo(abbrev: "MTL", name: "Montréal Canadiens",     primaryHex: 0xC8102E, secondaryHex: 0x192168), // red / blue
        TeamInfo(abbrev: "NSH", name: "Nashville Predators",    primaryHex: 0xFFB81C, secondaryHex: 0x041E42), // gold / navy
        TeamInfo(abbrev: "NJD", name: "New Jersey Devils",      primaryHex: 0xCE1126, secondaryHex: 0x000000), // red / black
        TeamInfo(abbrev: "NYI", name: "New York Islanders",     primaryHex: 0x00539B, secondaryHex: 0xF47D30), // blue / orange
        TeamInfo(abbrev: "NYR", name: "New York Rangers",       primaryHex: 0x0038A8, secondaryHex: 0xCE1126), // blue / red
        TeamInfo(abbrev: "OTT", name: "Ottawa Senators",        primaryHex: 0xC8102E, secondaryHex: 0xC2912C), // red / gold
        TeamInfo(abbrev: "PHI", name: "Philadelphia Flyers",    primaryHex: 0xF74902, secondaryHex: 0x000000), // orange / black
        TeamInfo(abbrev: "PIT", name: "Pittsburgh Penguins",    primaryHex: 0x000000, secondaryHex: 0xFCB514), // black / gold
        TeamInfo(abbrev: "SJS", name: "San Jose Sharks",        primaryHex: 0x006D75, secondaryHex: 0xEA7200), // teal / orange
        TeamInfo(abbrev: "SEA", name: "Seattle Kraken",         primaryHex: 0x00539B, secondaryHex: 0x99D9D9), // bright blue / ice blue
        TeamInfo(abbrev: "STL", name: "St. Louis Blues",        primaryHex: 0x0046AD, secondaryHex: 0xFCB514), // bright blue / gold
        TeamInfo(abbrev: "TBL", name: "Tampa Bay Lightning",    primaryHex: 0x00205B, secondaryHex: 0xFFFFFF), // navy / white
        TeamInfo(abbrev: "TOR", name: "Toronto Maple Leafs",    primaryHex: 0x00205B, secondaryHex: 0xFFFFFF), // navy / white
        TeamInfo(abbrev: "VAN", name: "Vancouver Canucks",      primaryHex: 0x00205B, secondaryHex: 0x00843D), // navy / green
        TeamInfo(abbrev: "VGK", name: "Vegas Golden Knights",   primaryHex: 0xB4975A, secondaryHex: 0x333F42), // gold / steel grey
        TeamInfo(abbrev: "WSH", name: "Washington Capitals",    primaryHex: 0xC8102E, secondaryHex: 0x041E42), // red / navy
        TeamInfo(abbrev: "WPG", name: "Winnipeg Jets",          primaryHex: 0x004C97, secondaryHex: 0xFFFFFF), // bright blue / white
        TeamInfo(abbrev: "UTA", name: "Utah Mammoth",           primaryHex: 0x6CACE4, secondaryHex: 0x111111), // mountain blue / black
    ]
}
