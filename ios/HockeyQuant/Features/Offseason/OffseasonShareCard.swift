import SwiftUI

/// The social share card: a branded, self-contained snapshot of the user's
/// offseason timeline, rendered offscreen via ImageRenderer. Fixed width so
/// it exports at a consistent aspect for feeds/screenshots.
struct OffseasonShareCard: View {
    let moves: [GMMove]
    var store: OffseasonStore

    private let width: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(moves.prefix(10).enumerated()), id: \.element.id) { i, move in
                    moveRow(index: i + 1, move: move)
                }
                if moves.count > 10 {
                    Text("+ \(moves.count - 10) more moves")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            footer
        }
        .padding(26)
        .frame(width: width, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x101623), Color(hex: 0x1A2333)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "hockey.puck.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFF9500))
                Text("HOCKEYQUANT · OFFSEASON GM")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("My offseason,\nas the GM")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("\(moves.count) move\(moves.count == 1 ? "" : "s") · built on real cap space")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func moveRow(index: Int, move: GMMove) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(move.kind == .signing ? Color(hex: 0xD7263D) : Color(hex: 0xFF9500))
                Text("\(index)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                if move.kind == .signing {
                    Text(move.headline)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(move.teamA ?? "?") ↔ \(move.teamB ?? "?")")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(tradeSummary(move))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tradeSummary(_ move: GMMove) -> String {
        let out = (move.piecesAtoB ?? []).map(\.name).joined(separator: ", ")
        let inbound = (move.piecesBtoA ?? []).map(\.name).joined(separator: ", ")
        return "\(move.teamA ?? "?") send \(out.isEmpty ? "—" : out) for \(inbound.isEmpty ? "—" : inbound)"
    }

    private var footer: some View {
        HStack {
            Text("What would you do differently?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text("HockeyQuant")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.top, 6)
    }
}
