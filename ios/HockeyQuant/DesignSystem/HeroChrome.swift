import SwiftUI

// Venmo-style page chrome, in HockeyQuant's palette: a colored header band with
// a curved bottom edge (and optional overlapping avatar), 3-up action tiles, a
// big pill segmented control, and tall capsule action buttons.

// MARK: - Curved header band

/// The band's silhouette: square top, bottom edge bowing downward at the center.
struct ArcBandShape: Shape {
    var dip: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - dip))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - dip),
                       control: CGPoint(x: rect.midX, y: rect.maxY + dip))
        p.closeSubpath()
        return p
    }
}

/// A colored hero header with a curved bottom edge. `centerpiece` (e.g. an
/// avatar / tier badge) straddles the curve, half in the band and half out —
/// leave room below via `centerpieceOverhang` when it's set.
struct HeroBand<Content: View, Centerpiece: View>: View {
    var tint: Color = Theme.Palette.accent
    var dip: CGFloat = 26
    var centerpieceOverhang: CGFloat = 34
    @ViewBuilder var content: () -> Content
    @ViewBuilder var centerpiece: () -> Centerpiece

    var body: some View {
        content()
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, dip + Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                ArcBandShape(dip: dip)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.86)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(alignment: .bottom) {
                centerpiece().offset(y: centerpieceOverhang)
            }
            .padding(.bottom, centerpieceOverhang)
    }
}

extension HeroBand where Centerpiece == EmptyView {
    init(tint: Color = Theme.Palette.accent, dip: CGFloat = 26,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(tint: tint, dip: dip, centerpieceOverhang: 0,
                  content: content, centerpiece: { EmptyView() })
    }
}

/// A small translucent pill for text/controls sitting on the colored band.
struct BandPill: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .bold)) }
            Text(text).font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.white.opacity(0.18))
        .clipShape(Capsule())
    }
}

/// A round translucent icon button for the band's top corners.
struct BandIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        PressableButton(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.18))
                .clipShape(Circle())
        }
    }
}

// MARK: - Action tile (3-up quick actions)

/// A bordered quick-action tile: icon in a tinted circle over a bold label.
struct ActionTile: View {
    let icon: String
    let title: String
    var tint: Color = Theme.Palette.accent

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 52, height: 52)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.Palette.border, lineWidth: 1))
    }
}

// MARK: - Big pill segment control

/// A tall two/three-option pill switcher with a sliding thumb.
struct BigSegment: View {
    @Binding var selection: Int
    let options: [String]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = i }
                } label: {
                    Text(options[i])
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selection == i ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background {
                            if selection == i {
                                Capsule()
                                    .fill(Theme.Palette.surfaceRaised)
                                    .shadow(color: .black.opacity(0.10), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "seg-thumb", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.Palette.border.opacity(0.45)))
    }
}

// MARK: - Tall capsule action label

/// The balance-card button pair style: a tall bold capsule, filled (prominent)
/// or quiet. Use as the label of a Button / NavigationLink.
struct CapsuleActionLabel: View {
    let title: String
    var systemImage: String? = nil
    var prominent = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 13, weight: .bold)) }
            Text(title).font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.Palette.textPrimary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Capsule().fill(prominent ? AnyShapeStyle(Theme.Palette.accent)
                                             : AnyShapeStyle(Theme.Palette.border.opacity(0.45))))
    }
}
