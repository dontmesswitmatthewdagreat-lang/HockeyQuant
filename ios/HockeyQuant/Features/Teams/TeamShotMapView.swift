import SwiftUI

/// A team's shot map aggregated over its recent games — every shot mirrored onto
/// one attacking half. Defaults to a heat map (it's dense); Dots toggle available.
struct TeamShotMapView: View {
    let team: String

    /// Centre ice to the end boards. The backend folds every shot onto this half,
    /// so it's the only part of the sheet with anything in it.
    private static let zone = RinkGeometry.attackingHalf

    @State private var map: TeamShotMap?
    @State private var loading = true
    @State private var mode = 1            // 0 = Dots, 1 = Heatmap
    @State private var period: Int? = nil  // nil = all periods

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if loading {
                LoadingShimmer(height: 150)
            } else if let map, map.available, !map.shots.isEmpty {
                content(map)
            } else {
                Text("No recent shot data.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.md)
            }
        }
        .task {
            map = try? await APIClient(environment: .production).teamShotMap(team: team)
            loading = false
        }
    }

    @ViewBuilder
    private func content(_ map: TeamShotMap) -> some View {
        let color = TeamInfo.lookup(team).color
        let shots = filtered(map.shots)

        // Every shot is folded onto one attacking half, so drawing the far end
        // wastes half the canvas. Cropping to the half doubles the scale of
        // everything at the same width.
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width,
                              height: geo.size.width / RinkGeometry.aspect(Self.zone))
            ZStack(alignment: .topLeading) {
                RinkCanvas(xRange: Self.zone).frame(width: size.width, height: size.height)
                if mode == 0 {
                    ForEach(shots) { s in
                        marker(s, color: color)
                            .position(RinkGeometry.point(s.x, s.y, in: size, xRange: Self.zone))
                    }
                } else {
                    // Twice the rows to match the doubled height — otherwise the
                    // same cells just render bigger and the map looks blocky.
                    HeatCanvas(shots: shots, cols: 56, rows: 48, xRange: Self.zone)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(RinkGeometry.aspect(Self.zone), contentMode: .fit)

        HStack {
            Picker("", selection: $mode) {
                Text("Dots").tag(0); Text("Heatmap").tag(1)
            }
            .pickerStyle(.segmented).frame(width: 150)
            Spacer()
            if let s = map.summary {
                // Shot count follows the filter; games and rate stay season-level.
                Text(period == nil
                     ? "\(s.games) games · \(s.shots) shots · \(String(format: "%.0f", s.shotsPerGame))/gm"
                     : "\(s.games) games · \(shots.count) shots")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: Binding(get: { period ?? 0 },
                                          set: { period = $0 == 0 ? nil : $0 })) {
                Text("All").tag(0); Text("1st").tag(1); Text("2nd").tag(2); Text("3rd").tag(3)
            }
            .pickerStyle(.segmented)
            Text(periodNote)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    /// The 2nd period is the "long change" — benches are far from the defensive
    /// zone, tired lines get stuck out, and offence measurably rises. It's the one
    /// period where a team's shot pattern has a structural reason to differ.
    private var periodNote: String {
        switch period {
        case 1, 3: return "Short change — the bench is beside the defensive zone."
        case 2: return "Long change — the bench is far from the defensive zone, which tends to open up offence."
        default: return "Every shot is rotated onto one attacking end, so the left/right split reflects the shooter's side."
        }
    }

    private func filtered(_ shots: [ShotEvent]) -> [ShotEvent] {
        period == nil ? shots : shots.filter { $0.period == period }
    }

    private func marker(_ s: ShotEvent, color: Color) -> some View {
        Group {
            if s.isGoal {
                Circle().fill(color).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.white, lineWidth: 1))
            } else if s.isMiss {
                Circle().fill(color.opacity(0.25)).frame(width: 4, height: 4)
            } else {
                Circle().fill(color.opacity(0.6)).frame(width: 5, height: 5)
            }
        }
    }
}
