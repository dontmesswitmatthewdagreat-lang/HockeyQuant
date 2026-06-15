import SwiftUI
import Charts

/// Reliability diagram: how the model's win probabilities compare to actual win
/// rates. Points on the dashed diagonal = perfectly calibrated.
struct CalibrationCard: View {
    private let api = APIClient(environment: .production)
    @State private var data: CalibrationResponse?
    @State private var loading = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Model calibration")
                    .font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                Text("When the model says X%, does it actually happen X% of the time?")
                    .font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)

                if loading {
                    LoadingShimmer(height: 200)
                } else if let d = data, d.buckets.count >= 2 {
                    chart(d)
                    HStack(spacing: 6) {
                        Image(systemName: verdictIcon(d)).foregroundStyle(verdictColor(d))
                        Text("Within ±\(d.calibrationError, specifier: "%.1f")% of perfect — \(d.verdict)")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        Text("\(d.games) games").font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                } else {
                    Text("Not enough graded games yet.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, Theme.Spacing.md)
                }
            }
        }
        .task {
            data = try? await api.calibration()
            loading = false
        }
    }

    private func chart(_ d: CalibrationResponse) -> some View {
        Chart {
            // Perfect-calibration diagonal.
            ForEach([0.0, 100.0], id: \.self) { v in
                LineMark(x: .value("Predicted", v), y: .value("Actual", v), series: .value("s", "perfect"))
                    .foregroundStyle(Theme.Palette.textTertiary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            // Model reliability curve.
            ForEach(d.buckets) { b in
                LineMark(x: .value("Predicted", b.mid), y: .value("Actual", b.actualPct), series: .value("s", "model"))
                    .foregroundStyle(Theme.Palette.accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Predicted", b.mid), y: .value("Actual", b.actualPct))
                    .foregroundStyle(Theme.Palette.accent)
                    .symbolSize(40 + Double(b.n) / 3)
            }
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: [0, 25, 50, 75, 100]) }
        .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) }
        .chartXAxisLabel("Predicted win %", alignment: .center)
        .chartYAxisLabel("Actual win %")
        .frame(height: 200)
    }

    private func verdictIcon(_ d: CalibrationResponse) -> String {
        d.calibrationError < 5 ? "checkmark.seal.fill" : (d.calibrationError < 9 ? "checkmark.circle" : "exclamationmark.triangle")
    }
    private func verdictColor(_ d: CalibrationResponse) -> Color {
        d.calibrationError < 5 ? Theme.Palette.strong : (d.calibrationError < 9 ? Theme.Palette.accent : Theme.Palette.moderate)
    }
}
