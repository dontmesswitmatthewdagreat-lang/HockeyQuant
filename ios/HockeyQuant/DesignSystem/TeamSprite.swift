import SwiftUI

/// Hand-authored pixel-art emblems for team crests.
///
/// Same IP footing as `TeamGlyph`: every sprite depicts the ordinary thing the
/// team is *named* after — a shark, a flame, a bear — drawn from scratch here,
/// never traced from or fitted to a club's actual emblem. Being hand-authored
/// as code, there's also no generated-art provenance question and nothing to
/// license or attribute.
///
/// A sprite is a square grid of characters, one per pixel, and every color is
/// derived from `TeamInfo` — so the art themes itself per team and stays in
/// step if a palette is ever retuned.
///
///   `.` transparent   `X` body      `L` body, lightened
///   `D` body, darkened                `E` cut out to the disc color
///
/// `E` is the trick that makes eyes read: it paints the crest's own background
/// color, so the shape looks punched through rather than drawn on.
struct TeamSprite {
    let rows: [String]

    /// Grid resolution — sprites are square, so this is both width and height.
    var resolution: Int { rows.count }

    static func sprite(for abbrev: String) -> TeamSprite? {
        sprites[abbrev.uppercased()]
    }

    /// Proof-of-concept set, one per shape class the other 29 teams fall into:
    /// an abstract element, a face, and an angular emblem.
    ///
    /// Long horizontal silhouettes with thin appendages — a shark, a jet — are
    /// the hard case at this resolution and want a 24×24 grid; a 16×16 body
    /// tapering into a tail fin collapses into a diamond no matter how the
    /// fins are placed.
    private static let sprites: [String: TeamSprite] = [

        // Calgary — flame with a hot core.
        "CGY": TeamSprite(rows: [
            "................",
            ".......X........",
            "......XX........",
            ".....XXX........",
            ".....XXXX..X....",
            "....XXXXX.XX....",
            "...XXXXXXXXX....",
            "...XXXXXXXXXX...",
            "..XXXXXLLXXXXX..",
            "..XXXXLLLLXXXX..",
            "..XXXXLLLLXXXX..",
            "..XXXXXLLXXXXX..",
            "...XXXXXXXXXX...",
            "....XXXXXXXX....",
            ".....XXXXXX.....",
            "................",
        ]),

        // Boston — bear, front-facing.
        "BOS": TeamSprite(rows: [
            "................",
            "..XX........XX..",
            ".XXXX......XXXX.",
            ".XXXX......XXXX.",
            "..XXXXXXXXXXXX..",
            ".XXXXXXXXXXXXXX.",
            "XXXXXXXXXXXXXXXX",
            "XXXEEXXXXXXEEXXX",
            "XXXEEXXXXXXEEXXX",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXDDXXXXXXX",
            ".XXXXXDDDDXXXXX.",
            ".XXXXXXDDXXXXXX.",
            "..XXXXXXXXXXXX..",
            "....XXXXXXXX....",
            "................",
        ]),

        // Toronto — a plain maple leaf: the national symbol, not the club's
        // own many-pointed mark.
        "TOR": TeamSprite(rows: [
            "................",
            "................",
            "...X...XX...X...",
            "...XX.XXXX.XX...",
            "....XXXXXXXX....",
            ".X..XXXXXXXX..X.",
            ".XXXXXXXXXXXXXX.",
            "..XXXXXXXXXXXX..",
            "...XXXXXXXXXX...",
            "....XXXXXXXX....",
            "...XXXX..XXXX...",
            "......XXXX......",
            ".......XX.......",
            ".......XX.......",
            "................",
            "................",
        ]),
    ]
}

/// Draws a `TeamSprite` as crisp, unsmoothed pixels.
struct PixelSpriteView: View {
    let sprite: TeamSprite
    /// Main color of the art (the crest's contrast-safe emblem color).
    let ink: Color
    /// The color behind the sprite, painted into `E` pixels as a cut-out.
    let cut: Color

    var body: some View {
        Canvas { ctx, size in
            let n = sprite.resolution
            let step = size.width / CGFloat(n)
            for (r, row) in sprite.rows.enumerated() {
                for (c, ch) in row.enumerated() where ch != "." {
                    // Snap each cell to whole points and derive its size from
                    // the neighbor's edge, so pixels tile seamlessly instead of
                    // leaving hairline gaps at fractional scales.
                    let x0 = (CGFloat(c) * step).rounded(.down)
                    let y0 = (CGFloat(r) * step).rounded(.down)
                    let x1 = (CGFloat(c + 1) * step).rounded(.down)
                    let y1 = (CGFloat(r + 1) * step).rounded(.down)
                    let cell = Path(CGRect(x: x0, y: y0,
                                           width: max(1, x1 - x0),
                                           height: max(1, y1 - y0)))
                    switch ch {
                    case "X":
                        ctx.fill(cell, with: .color(ink))
                    case "L":
                        ctx.fill(cell, with: .color(ink))
                        ctx.fill(cell, with: .color(.white.opacity(0.45)))
                    case "D":
                        ctx.fill(cell, with: .color(ink))
                        ctx.fill(cell, with: .color(.black.opacity(0.40)))
                    case "E":
                        ctx.fill(cell, with: .color(cut))
                    default:
                        break
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
