import SwiftUI

/// Horizontal scrolling day picker (weekday + date + game-count dots), centered on
/// the selected day. `onBand` styles the cells for the colored hero band (white
/// translucent chrome) instead of the page background.
struct DayStripView: View {
    let model: TodayViewModel
    var onBand = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(model.stripDays, id: \.self) { day in
                        DayCell(
                            day: day,
                            selected: model.isSelected(day),
                            isToday: Calendar.current.isDateInToday(day),
                            dots: model.dots(for: day),
                            onBand: onBand
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
    let onBand: Bool
    let action: () -> Void

    private static let weekdayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()

    private var weekdayColor: Color {
        if onBand { return selected ? .white : .white.opacity(0.65) }
        return selected ? Theme.Palette.accent : Theme.Palette.textTertiary
    }
    private var dayColor: Color {
        if onBand { return selected ? Theme.Palette.textPrimary : .white.opacity(0.9) }
        return selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary
    }
    private var cellFill: Color {
        if onBand { return selected ? Theme.Palette.surfaceRaised : .white.opacity(0.12) }
        return selected ? Theme.Palette.surface : .clear
    }
    private var dotColor: Color {
        if onBand { return selected ? Theme.Palette.accent : .white.opacity(0.8) }
        return selected ? Theme.Palette.accent : Theme.Palette.textTertiary
    }

    var body: some View {
        PressableButton(action: action) {
            VStack(spacing: 4) {
                dotsRow
                Text(Self.weekdayFmt.string(from: day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(weekdayColor)
                Text(Self.dayFmt.string(from: day))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected && onBand ? Theme.Palette.textPrimary : dayColor)
            }
            .frame(width: 46)
            .padding(.vertical, Theme.Spacing.xs)
            .background(cellFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(selected ? (onBand ? .white : Theme.Palette.accent) : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .bottom) {
                if isToday && !selected {
                    Circle().fill(onBand ? .white : Theme.Palette.accent)
                        .frame(width: 4, height: 4).offset(y: 3)
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
                    Circle().fill(dotColor).frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 5)
    }
}
