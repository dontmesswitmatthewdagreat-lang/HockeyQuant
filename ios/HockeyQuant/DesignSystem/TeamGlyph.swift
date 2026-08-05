import SwiftUI

/// The emblem inside a team crest.
///
/// Teams are *named* after generic things — a flame, a star, a shark, an oil
/// drop — and no club can own the underlying concept; what's protected is its
/// specific artwork. So every glyph here is drawn from the generic noun and
/// never approximates a real NHL mark, wordmark, or mascot rendering. The art
/// itself is Apple's SF Symbols, licensed for use as in-app iconography.
///
/// Two rules keep this defensible, and both matter if the table is ever edited:
/// pick the ordinary object the name refers to, and if the only faithful
/// depiction would be the club's own emblem, pick something else about the city
/// instead (Chicago is wind, not the head on the sweater).
enum TeamGlyph {

    /// Generic-concept emblem per team, all 32 distinct. Sharing a silhouette
    /// between two teams reads as a bug in the Statistics → Teams grid, which
    /// shows every crest at once — so where the obvious noun was taken, the
    /// glyph falls back to the city (Pittsburgh's steel, Utah's beehive).
    private static let symbols: [String: String] = [
        // Atlantic
        "BOS": "pawprint.fill",              // bear
        "BUF": "figure.fencing",             // sabre
        "DET": "gearshape.fill",             // Motor City
        "FLA": "cat.fill",                   // panther
        "MTL": "fleuron.fill",               // Québec fleur-de-lis
        "OTT": "building.columns.fill",      // senate
        "TBL": "bolt.fill",                  // lightning
        "TOR": "leaf.fill",                  // maple leaf

        // Metropolitan
        "CAR": "hurricane",                  // hurricane
        "CBJ": "flag.fill",                  // Civil War regiment
        "NJD": "tuningfork",                 // trident
        "NYI": "sailboat.fill",              // the Sound
        "NYR": "shield.fill",                // heraldry
        "PHI": "bell.fill",                  // Liberty Bell
        "PIT": "hammer.fill",                // the Steel City
        "WSH": "sparkles",                   // capital stars

        // Central
        "CHI": "wind",                       // the Windy City
        "COL": "snowflake",                  // avalanche
        "DAL": "star.fill",                  // star
        "MIN": "tree.fill",                  // north woods
        "NSH": "music.mic",                  // Music City
        "STL": "music.note",                 // blues
        "UTA": "hexagon.fill",               // the Beehive State
        "WPG": "airplane",                   // jet

        // Pacific
        "ANA": "bird.fill",                  // duck
        "CGY": "flame.fill",                 // flame
        "EDM": "drop.fill",                  // oil
        "LAK": "crown.fill",                 // king
        "SJS": "fish.fill",                  // shark
        "SEA": "water.waves",                // kraken
        "VAN": "mountain.2.fill",            // North Shore
        "VGK": "shield.lefthalf.filled",     // knight's shield
    ]

    /// The SF Symbol for a team, or nil when we have no mapping (unknown
    /// abbreviation) and the crest should fall back to its monogram.
    static func symbol(for abbrev: String) -> String? {
        symbols[abbrev.uppercased()]
    }

    /// Below this the art turns to mud and the monogram reads better.
    static let minimumLegibleSize: CGFloat = 20
}
