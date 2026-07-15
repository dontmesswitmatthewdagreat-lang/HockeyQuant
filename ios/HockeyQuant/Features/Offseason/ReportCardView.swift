import SwiftUI

/// Compact grade banner for a team's offseason — the entry point that opens
/// the full report card. Tinted by the letter grade.
struct ReportCardBanner: View {
    let card: OffseasonReportCard
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                gradeBadge(card.grade, hex: card.gradeHex, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        CrestView(abbrev: card.team, size: 18)
                        Text("Offseason Report Card")
                            .font(.system(size: 12, weight: .heavy))
                            .kerning(0.6)
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Text(card.headline)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .strokeBorder(Color(hex: card.gradeHex).opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The full graded breakdown: big grade, the factors behind it, arrivals /
/// departures / re-signings with verdicts, the draft desk, and a share card.
struct ReportCardSheet: View {
    let card: OffseasonReportCard

    private var teamName: String { TeamInfo.lookup(card.team).name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if !card.factors.isEmpty {
                    SectionCard("How the grade was earned") { factorList }
                }
                movesCard("Arrivals", card.arrivals, otherLabel: "from")
                movesCard("Re-signings", card.resigned, otherLabel: nil)
                movesCard("Departures", card.departures, otherLabel: "to")
                draftCard
                shareButton
                Text("Grades weigh signings against the player market's fair value, talent in vs out, what rivals paid the players who left, and the draft desk. Deterministic — every point traces to a row above.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.md)
        }
        .frame(maxHeight: 640)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            gradeBadge(card.grade, hex: card.gradeHex, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    CrestView(abbrev: card.team, size: 24)
                    Text(teamName)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(card.headline)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.sm) {
                    statChip("COMMITTED", String(format: "$%.1fM", card.committed / 1_000_000), nil)
                    statChip("VALUE",
                             String(format: "%@$%.1fM", card.surplus >= 0 ? "+" : "−",
                                    abs(card.surplus) / 1_000_000),
                             card.surplus >= 0 ? Theme.Palette.positive : Theme.Palette.negative)
                }
                .padding(.top, 2)
            }
        }
    }

    private func statChip(_ label: String, _ value: String, _ tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint ?? Theme.Palette.textPrimary)
        }
    }

    // MARK: - Factors

    private var factorList: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(card.factors) { f in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: f.positive ? "plus.circle.fill" : "minus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(f.positive ? Theme.Palette.positive : Theme.Palette.negative)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.label)
                            .font(.system(size: 10, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(Theme.Palette.textTertiary)
                        Text(f.detail)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Moves

    @ViewBuilder
    private func movesCard(_ title: String, _ moves: [ReportCardMove], otherLabel: String?) -> some View {
        if !moves.isEmpty {
            SectionCard("\(title) · \(moves.count)") {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(moves) { m in moveRow(m, otherLabel: otherLabel) }
                }
            }
        }
    }

    private func moveRow(_ m: ReportCardMove, otherLabel: String?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let other = m.otherTeam {
                CrestView(abbrev: other, size: 26)
            } else {
                Text(m.position)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.Palette.surfaceRaised))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(otherLabel.flatMap { l in m.otherTeam.map { "\(m.termLine) · \(l) \($0)" } } ?? m.termLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let v = m.verdict {
                StatusPill(text: v.verdictLabel,
                           color: v == "steal" ? Theme.Palette.positive
                                : v == "overpay" ? Theme.Palette.negative
                                : Theme.Palette.textSecondary,
                           solid: v != "fair")
            }
        }
    }

    // MARK: - Draft

    private var draftCard: some View {
        SectionCard("Draft desk") {
            HStack(spacing: Theme.Spacing.md) {
                draftStat("\(card.draft.picks)", "PICKS")
                if let overall = card.draft.firstOverall {
                    draftStat("#\(overall)", "FIRST PICK")
                }
                draftStat("\(card.draft.elcSigned)", "ELCs SIGNED")
                Spacer(minLength: 0)
            }
            if let player = card.draft.firstPlayer {
                Text("Headlined by \(player)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private func draftStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    // MARK: - Share

    @ViewBuilder
    private var shareButton: some View {
        if let image = renderShareCard() {
            ShareLink(item: image, preview: SharePreview("\(teamName) offseason grade", image: image)) {
                CapsuleActionLabel(title: "Share the grade", systemImage: "square.and.arrow.up", prominent: true)
            }
            .buttonStyle(.plain)
        }
    }

    @MainActor
    private func renderShareCard() -> Image? {
        let renderer = ImageRenderer(content: ReportCardShareCard(card: card, teamName: teamName))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

/// A branded, self-contained snapshot for feeds/screenshots.
struct ReportCardShareCard: View {
    let card: OffseasonReportCard
    let teamName: String

    private let width: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "hockey.puck.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFF9500))
                Text("HOCKEYQUANT · OFFSEASON GRADE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack(alignment: .center, spacing: 18) {
                gradeBadge(card.grade, hex: card.gradeHex, size: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(teamName)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(card.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(card.factors.prefix(4)) { f in
                    HStack(spacing: 10) {
                        Image(systemName: f.positive ? "plus.circle.fill" : "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(f.positive ? Color(hex: 0x35C489) : Color(hex: 0xE8686F))
                        Text(f.detail)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            Text("Graded by the HockeyQuant player market")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(26)
        .frame(width: width, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x101623), Color(hex: 0x1A2333)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

/// The letter grade in a tinted rounded square — shared by banner, sheet, share.
@ViewBuilder
func gradeBadge(_ grade: String, hex: UInt32, size: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        .fill(
            LinearGradient(colors: [Color(hex: hex), Color(hex: hex).opacity(0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .frame(width: size, height: size)
        .overlay(
            Text(grade)
                .font(.system(size: size * 0.44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .padding(2)
        )
        .shadow(color: Color(hex: hex).opacity(0.4), radius: 6, y: 3)
}
