import SwiftUI

/// A team's shot map aggregated over its recent games — every shot mirrored onto
/// one attacking half. Defaults to a heat map (it's dense); Dots toggle available.
struct TeamShotMapView: View {
    let team: String

    @State private var map: TeamShotMap?
    @State private var loading = true
    @State private var mode = 1   // 0 = Dots, 1 = Heatmap

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

        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: geo.size.width * 85 / 200)
            ZStack(alignment: .topLeading) {
                RinkCanvas().frame(width: size.width, height: size.height)
                if mode == 0 {
                    ForEach(map.shots) { s in
                        marker(s, color: color).position(RinkGeometry.point(s.x, s.y, in: size))
                    }
                } else {
                    HeatCanvas(shots: map.shots).frame(width: size.width, height: size.height).allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(200.0 / 85.0, contentMode: .fit)

        HStack {
            Picker("", selection: $mode) {
                Text("Dots").tag(0); Text("Heatmap").tag(1)
            }
            .pickerStyle(.segmented).frame(width: 150)
            Spacer()
            if let s = map.summary {
                Text("\(s.games) games · \(s.shots) shots · \(s.shotsPerGame, specifier: "%.0f")/gm")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
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
