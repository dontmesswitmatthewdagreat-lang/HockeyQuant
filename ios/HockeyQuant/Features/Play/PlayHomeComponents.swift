import SwiftUI

// Components for the Rocket Money-style Play home: a personal greeting, a
// big-balance Cap Space hero, the slate progress ring with compact game rows,
// and grouped mode rows. Data comes pre-loaded from GamificationStore.

// MARK: - Section label

/// A small-caps segment header with a short accent tick and an optional trailing accessory.
struct SectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.textPrimary)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.Palette.accent)
                .frame(width: 16, height: 3)
            Spacer(minLength: Theme.Spacing.xs)
            trailing()
        }
        .padding(.horizontal, 2)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title, trailing: { EmptyView() }) }
}

/// A compact pill chip used for the season tag and small stat callouts.
struct PillChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Theme.Palette.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - Slate progress ring

/// The signature progress ring: how much of tonight's slate you've called.
struct SlateRing: View {
    let picked: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(picked) / Double(total) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.background, lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(total > 0 ? 0.02 : 0, fraction))
                .stroke(AngularGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt, Theme.Palette.accent],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7), value: fraction)
            VStack(spacing: 0) {
                Text("\(picked)/\(max(total, 0))")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                Text("CALLED")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(width: 68, height: 68)
    }
}

// MARK: - Slate game row (bill-style)

/// A compact "upcoming bill"-style row for one game: overlapping crests, the
/// matchup, the model's lean + start time, and the pick state. Tap → pick sheet.
struct SlateGameRow: View {
    let game: GamePrediction
    let pick: UserPick?

    private var graded: Bool { pick?.correct != nil }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                CrestView(abbrev: game.away.team, size: 30).offset(x: -9)
                CrestView(abbrev: game.home.team, size: 30).offset(x: 9)
            }
            .frame(width: 52, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.away.info.abbrev) @ \(game.home.info.abbrev)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            trailingState
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = ["Model: \(game.pick)"]
        if let t = startTime { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var trailingState: some View {
        if graded {
            let correct = pick?.correct == true
            HStack(spacing: 4) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(correct ? Theme.Palette.positive : Theme.Palette.negative)
                Text(correct ? "+\(pick?.xpAwarded ?? 0)" : "Missed")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(correct ? Theme.Palette.positive : Theme.Palette.negative)
            }
        } else if let pick {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                Text(pick.pick.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.Palette.accent.opacity(0.14))
            .clipShape(Capsule())
        } else {
            HStack(spacing: 2) {
                Text("Call")
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.Palette.accent)
        }
    }

    private var startTime: String? {
        guard let iso = game.gameTime, let date = Self.isoParser.date(from: iso) else { return nil }
        return Self.timeFmt.string(from: date)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
}

// MARK: - Mode row (grouped-list style)

/// A grouped-list row: icon in a tinted rounded square, title + subtitle, and a
/// trailing value + chevron (the subscriptions-list pattern).
struct ModeRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var value: String? = nil
    var valueCaption: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if value != nil || valueCaption != nil {
                VStack(alignment: .trailing, spacing: 1) {
                    if let value {
                        Text(value)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    if let valueCaption {
                        Text(valueCaption)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .contentShape(Rectangle())
    }
}
