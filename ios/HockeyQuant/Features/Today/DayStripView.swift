import SwiftUI

/// Horizontal scrolling day picker (weekday + date + game-count dots), centered on
/// the selected day. Inspired by a calendar-strip layout; uses the app's theme.
struct DayStripView: View {
    let model: TodayViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(model.stripDays, id: \.self) { day in
                        DayCell(
                            day: day,
                            selected: model.isSelected(day),
                            isToday: Calendar.current.isDateInToday(day),
                            dots: model.dots(for: day)
                        ) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { model.select(day) }
                        }
                        .id(dayID(day))
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .onAppear { proxy.scrollTo(dayID(model.selectedDate), anchor: .center) }
            .onChange(of: model.selectedDate) { _, d in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo(dayID(d), anchor: .center)
                }
            }
        }
    }

    private func dayID(_ d: Date) -> String { APIClient.apiDateString(d) }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let isToday: Bool
    let dots: Int
    let action: () -> Void

    private static let weekdayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()

    var body: some View {
        PressableButton(action: action) {
            VStack(spacing: 4) {
                dotsRow
                Text(Self.weekdayFmt.string(from: day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.Palette.accent : Theme.Palette.textTertiary)
                Text(Self.dayFmt.string(from: day))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            }
            .frame(width: 46)
            .padding(.vertical, Theme.Spacing.xs)
            .background(selected ? Theme.Palette.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(selected ? Theme.Palette.accent : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .bottom) {
                if isToday && !selected {
                    Circle().fill(Theme.Palette.accent).frame(width: 4, height: 4).offset(y: 3)
                }
            }
        }
        .accessibilityLabel("\(Self.weekdayFmt.string(from: day)) \(Self.dayFmt.string(from: day))\(dots > 0 ? ", \(dots) games" : "")")
    }

    private var dotsRow: some View {
        HStack(spacing: 3) {
            if dots == 0 {
                Circle().fill(Color.clear).frame(width: 4, height: 4)
            } else {
                ForEach(0..<dots, id: \.self) { _ in
                    Circle()
                        .fill(selected ? Theme.Palette.accent : Theme.Palette.textTertiary)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 5)
    }
}
