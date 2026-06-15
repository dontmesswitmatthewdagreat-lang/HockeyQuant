import SwiftUI

/// An original, designed team "crest" — a colored roundel/badge with the team's
/// abbreviation monogram. Distinctive team branding WITHOUT using NHL logos
/// (avoids trademark/IP exposure). Driven by `TeamInfo` colors.
struct CrestView: View {
    let abbrev: String
    var size: CGFloat = 48

    private var info: TeamInfo { TeamInfo.lookup(abbrev) }

    var body: some View {
        ZStack {
            // Primary team color with subtle top-light / bottom-shade for depth.
            Circle()
                .fill(info.primary)
                .overlay(
                    Circle().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.clear, Color.black.opacity(0.22)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                )

            // Crest chevron accent across the lower third.
            Chevron()
                .fill(Color.white.opacity(0.16))
                .frame(width: size, height: size * 0.42)
                .offset(y: size * 0.20)
                .mask(Circle())

            // Hairline ring.
            Circle().stroke(Color.white.opacity(0.30), lineWidth: max(1, size * 0.035))

            // Monogram in the secondary color (contrast-safe).
            Text(info.abbrev)
                .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                .foregroundStyle(info.crestMonogram)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.25), radius: size * 0.02, y: size * 0.01)
                .padding(.horizontal, size * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(info.name) crest")
    }

    /// An upward chevron used as a subtle crest band.
    private struct Chevron: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + rect.height))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + rect.height))
            p.closeSubpath()
            return p
        }
    }
}
