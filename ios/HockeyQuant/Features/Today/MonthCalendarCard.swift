import SwiftUI

/// The app's own month calendar (replaces the stock graphical DatePicker):
/// game-count dots under each day, accent selection ring, spring month paging.
/// Presented inside a floating card.
struct MonthCalendarCard: View {
    @Binding var selection: Date
    let gameCounts: [String: Int]
    var onPick: () -> Void = {}
    var onMonthChange: (Date) -> Void = { _ in }

    @State private var visibleMonth: Date
    @State private var pageDirection: Int = 0   // -1 back, +1 forward (drives transition)

    private let cal = Calendar.current

    init(selection: Binding<Date>, gameCounts: [String: Int],
         onPick: @escaping () -> Void = {},
         onMonthChange: @escaping (Date) -> Void = { _ in }) {
        _selection = selection
        self.gameCounts = gameCounts
        _visibleMonth = State(initialValue: Calendar.current.startOfDay(for: selection.wrappedValue))
        self.onPick = onPick
        self.onMonthChange = onMonthChange
    }

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            header
            weekdayRow
            monthGrid
                .id(monthKey)
                .transition(.asymmetric(
                    insertion: .move(edge: pageDirection >= 0 ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: pageDirection >= 0 ? .leading : .trailing).combined(with: .opacity)))
            legend
        }
        .padding(Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    private var monthKey: String {
        let c = cal.dateComponents([.year, .month], from: visibleMonth)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Self.monthFmt.string(from: visibleMonth))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Spacer()
            pagerButton("chevron.left") { page(-1) }
            pagerButton("chevron.right") { page(1) }
        }
        .padding(.trailing, 34)   // room for the card's close button
    }

    private func pagerButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 32, height: 32)
                .background(Theme.Palette.surface)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func page(_ dir: Int) {
        pageDirection = dir
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            visibleMonth = cal.date(byAdding: .month, value: dir, to: visibleMonth) ?? visibleMonth
        }
        onMonthChange(visibleMonth)
    }

    // MARK: - Grid

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols   // ordered Sun-first
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Weeks of the visible month (nil = leading/trailing blank cell).
    private var weeks: [[Date?]] {
        guard let interval = cal.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstDay = interval.start
        let dayCount = cal.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        let leading = (cal.component(.weekday, from: firstDay) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: d, to: firstDay))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var monthGrid: some View {
        VStack(spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 46)
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { v in
                    if abs(v.translation.width) > abs(v.translation.height) {
                        page(v.translation.width < 0 ? 1 : -1)
                    }
                }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: selection)
        let isToday = cal.isDateInToday(day)
        let games = min(gameCounts[APIClient.apiDateString(day)] ?? 0, 3)
        return Button {
            Haptics.tap()
            selection = cal.startOfDay(for: day)
            onPick()
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(.system(size: 15, weight: selected ? .heavy : .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white : Theme.Palette.textPrimary)
                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < games
                                  ? (selected ? .white : Theme.Palette.accent)
                                  : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if selected {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                } else if isToday {
                    Circle()
                        .strokeBorder(Theme.Palette.accent.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.Palette.accent).frame(width: 4, height: 4)
            Text("dots mark game days")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            Spacer()
        }
        .padding(.top, 2)
    }
}
