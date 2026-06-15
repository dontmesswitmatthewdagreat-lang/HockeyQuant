import SwiftUI

/// Per-game shot map: a drawn rink with each team's shots plotted by location,
/// goals highlighted. Toggle Dots ↔ Heatmap, replay shots in game order, filter
/// by period. Coordinates come normalized (home → +x, away → −x).
struct ShotMapView: View {
    let date: String
    let away: String
    let home: String

    @State private var map: GameShotMap?
    @State private var loading = true
    @State private var mode = 0            // 0 = Dots, 1 = Heatmap
    @State private var period: Int? = nil  // nil = all
    @State private var playing = false
    @State private var visible = Int.max   // how many (chrono) shots shown

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if loading {
                LoadingShimmer(height: 170)
            } else if let map, map.available, !map.shots.isEmpty {
                content(map)
            } else {
                unavailable
            }
        }
        .task {
            map = try? await APIClient(environment: .production).shotMap(date: date, away: away, home: home)
            loading = false
        }
        .onReceive(timer) { _ in tick() }
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "hockey.puck").font(.system(size: 26)).foregroundStyle(Theme.Palette.textTertiary)
            Text("Shot map appears once the puck drops.")
                .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.lg)
    }

    @ViewBuilder
    private func content(_ map: GameShotMap) -> some View {
        let shots = filtered(map.shots)
        let shown = playing ? Array(shots.prefix(min(visible, shots.count))) : shots

        // Rink + shots
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: geo.size.width * 85 / 200)
            ZStack(alignment: .topLeading) {
                RinkCanvas().frame(width: size.width, height: size.height)
                if mode == 0 {
                    ForEach(shown) { s in
                        marker(s).position(RinkGeometry.point(s.x, s.y, in: size))
                    }
                } else {
                    HeatCanvas(shots: shown).frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(200.0 / 85.0, contentMode: .fit)

        controls(map)
        legend(map)
    }

    private func marker(_ s: ShotEvent) -> some View {
        let color = TeamInfo.lookup(s.team).color
        return Group {
            if s.isGoal {
                ZStack {
                    Circle().fill(color).frame(width: 14, height: 14)
                    Circle().stroke(.white, lineWidth: 2).frame(width: 14, height: 14)
                    Image(systemName: "star.fill").font(.system(size: 6)).foregroundStyle(.white)
                }
                .shadow(color: color.opacity(0.6), radius: 3)
            } else if s.isMiss {
                Circle().stroke(color.opacity(0.7), lineWidth: 1.5).frame(width: 8, height: 8)
            } else {
                Circle().fill(color.opacity(0.9)).frame(width: 8, height: 8)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func controls(_ map: GameShotMap) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Picker("", selection: $mode) {
                Text("Dots").tag(0); Text("Heatmap").tag(1)
            }
            .pickerStyle(.segmented).frame(width: 150)

            Spacer()

            Picker("", selection: Binding(get: { period ?? 0 }, set: { period = $0 == 0 ? nil : $0 })) {
                Text("All").tag(0); Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
            }
            .pickerStyle(.segmented).frame(width: 150)

            if mode == 0 {
                Button { startReplay(map) } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Theme.Palette.accent).clipShape(Circle())
                }
                .accessibilityLabel("Replay shots")
            }
        }
    }

    private func legend(_ map: GameShotMap) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            teamLegend(map.away ?? away, map.summary?.away)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.Palette.textSecondary)
                Text("goal").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            teamLegend(map.home ?? home, map.summary?.home)
        }
    }

    private func teamLegend(_ team: String, _ s: ShotTeamSummary?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(TeamInfo.lookup(team).color).frame(width: 9, height: 9)
            Text(team).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Palette.textPrimary)
            if let s { Text("\(s.sog) SOG · \(s.goals)G").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary) }
        }
    }

    // MARK: - Replay

    private func filtered(_ shots: [ShotEvent]) -> [ShotEvent] {
        period == nil ? shots : shots.filter { $0.period == period }
    }

    private func startReplay(_ map: GameShotMap) {
        if playing { playing = false; return }
        visible = 0
        withAnimation { playing = true }
    }

    private func tick() {
        guard playing, let map else { return }
        let total = filtered(map.shots).count
        if visible >= total { playing = false; return }
        withAnimation(.spring(response: 0.25)) { visible += 1 }
    }
}

// MARK: - Rink geometry + drawing

enum RinkGeometry {
    static func point(_ x: Double, _ y: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: (x + 100) / 200 * size.width,
                y: (42.5 - y) / 85 * size.height)
    }
    static func dx(_ feet: Double, _ w: CGFloat) -> CGFloat { CGFloat((feet + 100) / 200) * w }
    static func dy(_ feet: Double, _ h: CGFloat) -> CGFloat { CGFloat((42.5 - feet) / 85) * h }
}

/// A simplified NHL rink drawn with Canvas — boards, lines, circles, creases, nets.
struct RinkCanvas: View {
    private let ice = Color(hex: 0xF3F8FD)
    private let red = Color(hex: 0xD7263D).opacity(0.55)
    private let blue = Color(hex: 0x2563EB).opacity(0.5)
    private let line = Color(hex: 0x9FB2C8).opacity(0.5)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let corner = h * 0.18
            let boards = Path(roundedRect: CGRect(x: 1, y: 1, width: w - 2, height: h - 2), cornerRadius: corner)
            ctx.fill(boards, with: .color(ice))
            ctx.stroke(boards, with: .color(line), lineWidth: 1.5)

            func vline(_ feet: Double, _ color: Color, _ lw: CGFloat) {
                let x = RinkGeometry.dx(feet, w)
                var p = Path(); p.move(to: CGPoint(x: x, y: 2)); p.addLine(to: CGPoint(x: x, y: h - 2))
                ctx.stroke(p, with: .color(color), lineWidth: lw)
            }
            vline(0, red, 2)         // center line
            vline(-25, blue, 2); vline(25, blue, 2)   // blue lines
            vline(-89, red, 1); vline(89, red, 1)     // goal lines

            func circle(_ fx: Double, _ fy: Double, r: CGFloat, color: Color, fill: Bool = false) {
                let c = RinkGeometry.point(fx, fy, in: size)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                if fill { ctx.fill(Path(ellipseIn: rect), with: .color(color)) }
                else { ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1) }
            }
            let zr = RinkGeometry.dy(42.5 - 15, h)  // 15ft radius in view units
            circle(0, 0, r: zr, color: blue)        // center circle
            circle(0, 0, r: 2.5, color: red, fill: true)
            for fx in [-69.0, 69.0] {
                for fy in [-22.0, 22.0] {
                    circle(fx, fy, r: zr, color: red)
                    circle(fx, fy, r: 2.5, color: red, fill: true)
                }
            }
            for fx in [-20.0, 20.0] {
                for fy in [-22.0, 22.0] { circle(fx, fy, r: 2.5, color: red, fill: true) }
            }
            // creases + nets at the goal lines
            for s in [-1.0, 1.0] {
                let gx = RinkGeometry.dx(89 * s, w)
                let cy = h / 2
                var crease = Path()
                crease.addArc(center: CGPoint(x: gx, y: cy), radius: RinkGeometry.dy(42.5 - 6, h),
                              startAngle: .degrees(s > 0 ? 110 : -70), endAngle: .degrees(s > 0 ? 250 : 70), clockwise: s > 0)
                ctx.stroke(crease, with: .color(blue), lineWidth: 1)
                let nw = RinkGeometry.dx(-100 + 4, w)
                let net = CGRect(x: gx - (s > 0 ? 0 : nw), y: cy - RinkGeometry.dy(42.5 - 3, h) / 1,
                                 width: nw, height: RinkGeometry.dy(42.5 - 3, h) * 2 / 1)
                ctx.stroke(Path(net), with: .color(red), lineWidth: 1)
            }
        }
    }
}

/// Density heat map: shots are binned into a rink grid, normalized to the busiest
/// cell, and ramped exponentially (gamma) so only real clusters glow bright while
/// sparse areas stay dim. Normalizing by the max makes it adapt to any shot volume.
struct HeatCanvas: View {
    let shots: [ShotEvent]
    private let cols = 56
    private let rows = 24
    private let gamma = 1.45

    var body: some View {
        Canvas { ctx, size in
            guard size.width > 0, size.height > 0, !shots.isEmpty else { return }
            var grid = [Double](repeating: 0, count: cols * rows)
            let kr = 2  // gaussian splat radius (cells)
            for s in shots {
                let p = RinkGeometry.point(s.x, s.y, in: size)
                let fx = p.x / size.width * Double(cols)
                let fy = p.y / size.height * Double(rows)
                let w = s.isGoal ? 1.6 : 1.0
                let gx0 = Int(fx), gy0 = Int(fy)
                for gx in max(0, gx0 - kr)...min(cols - 1, gx0 + kr) {
                    for gy in max(0, gy0 - kr)...min(rows - 1, gy0 + kr) {
                        let ddx = Double(gx) + 0.5 - fx, ddy = Double(gy) + 0.5 - fy
                        grid[gy * cols + gx] += w * exp(-(ddx * ddx + ddy * ddy) / 2.2)
                    }
                }
            }
            // Normalize by a high percentile (not the single max) so the broadly-hot
            // zone reads bright while one outlier cell doesn't dominate the scale.
            let nonzero = grid.filter { $0 > 0 }.sorted()
            guard let peak = nonzero.last, peak > 0 else { return }
            let norm = max(nonzero[Int(Double(nonzero.count) * 0.90)], peak * 0.15)
            let cw = size.width / Double(cols), ch = size.height / Double(rows)
            for gy in 0..<rows {
                for gx in 0..<cols {
                    let n = min(grid[gy * cols + gx] / norm, 1.0)
                    if n < 0.05 { continue }
                    let rect = CGRect(x: Double(gx) * cw, y: Double(gy) * ch, width: cw + 0.6, height: ch + 0.6)
                    ctx.fill(Path(rect), with: .color(Self.heatColor(pow(n, gamma))))
                }
            }
        }
        .blur(radius: 7)
    }

    /// dim blue → green → yellow → bright orange/red, alpha rising with intensity.
    static func heatColor(_ t: Double) -> Color {
        let stops: [(p: Double, h: Double, s: Double, b: Double, a: Double)] = [
            (0.00, 0.62, 0.85, 0.85, 0.00),
            (0.25, 0.60, 0.85, 0.95, 0.30),
            (0.50, 0.33, 0.85, 0.95, 0.55),
            (0.75, 0.13, 0.95, 1.00, 0.82),
            (1.00, 0.02, 0.95, 1.00, 0.95),
        ]
        var lo = stops[0], hi = stops[stops.count - 1]
        for i in 0..<stops.count - 1 where t >= stops[i].p && t <= stops[i + 1].p {
            lo = stops[i]; hi = stops[i + 1]; break
        }
        let f = min(max((t - lo.p) / max(hi.p - lo.p, 0.0001), 0), 1)
        func L(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        return Color(hue: L(lo.h, hi.h), saturation: L(lo.s, hi.s), brightness: L(lo.b, hi.b), opacity: L(lo.a, hi.a))
    }
}
