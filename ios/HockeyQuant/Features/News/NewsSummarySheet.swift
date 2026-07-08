import SwiftUI

/// Hold-to-summarize (Premium): pressing a news card shrinks it slightly and
/// lights up a gradient ring; after ~0.6s it fires with a haptic.
struct HoldToSummarize: ViewModifier {
    let action: () -> Void
    @State private var pressing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressing ? 0.965 : 1)
            .overlay {
                if pressing {
                    AnimatedGradientRing(cornerRadius: Theme.Radius.lg)
                        .transition(.opacity)
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .overlay {
                            Label("Hold for AI summary", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.black.opacity(0.55))
                                .clipShape(Capsule())
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pressing)
            .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 30) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                action()
            } onPressingChanged: { isPressing in
                pressing = isPressing
            }
    }
}

/// The quick-summary sheet: fetches a 3-4 sentence AI summary of the article
/// so the user never has to leave the app.
struct NewsSummarySheet: View {
    let item: DigestItem
    @Environment(\.openURL) private var openURL
    @State private var summary: String?
    @State private var failed = false
    private let api = APIClient()

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Label("AI summary", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                                       startPoint: .leading, endPoint: .trailing))
                            .clipShape(Capsule())
                        Text(item.source)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                        Spacer()
                    }
                    Text(item.headline)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Theme.Palette.border)
                    summaryBody
                    Button {
                        if let u = URL(string: item.url) { openURL(u) }
                    } label: {
                        CapsuleActionLabel(title: "Read full article", systemImage: "arrow.up.right", prominent: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Spacing.xs)
                }
                .padding(Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var summaryBody: some View {
        if let summary {
            Text(summary)
                .font(.system(size: 16))
                .lineSpacing(4)
                .foregroundStyle(Theme.Palette.textPrimary)
                .transition(.opacity)
        } else if failed {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Couldn't summarize this one.")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("The source may be blocking readers — the full article still works below.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.accent)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Reading the article…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                ForEach(0..<3, id: \.self) { _ in LoadingShimmer(height: 14) }
                LoadingShimmer(height: 14).padding(.trailing, 80)
            }
        }
    }

    private func load() async {
        do {
            let result = try await api.summarizeArticle(url: item.url, headline: item.headline, blurb: item.blurb)
            let text = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                failed = true
            } else {
                withAnimation(.easeOut(duration: 0.3)) { summary = text }
            }
        } catch {
            failed = true
        }
    }
}
