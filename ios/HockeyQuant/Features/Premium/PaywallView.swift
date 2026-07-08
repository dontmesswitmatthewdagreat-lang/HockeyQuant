import SwiftUI

/// The HockeyQuant Premium paywall sheet: what you get, the price, subscribe +
/// restore. Presented wherever a Premium feature is tapped by a free user.
struct PaywallView: View {
    @Environment(PremiumStore.self) private var premium
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    hero
                    features
                    subscribeButton
                    restoreRow
                    #if DEBUG
                    devRow
                    #endif
                    finePrint
                }
                .padding(Theme.Spacing.md)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.Palette.surfaceRaised)
                    .clipShape(Circle())
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.Palette.accent.opacity(0.35), radius: 16, y: 6)
                Image(systemName: "crown.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, Theme.Spacing.lg)
            Text("HockeyQuant Premium")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("\(premium.priceLabel)/month · cancel anytime")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var features: some View {
        VStack(spacing: Theme.Spacing.sm) {
            featureRow(icon: "arrow.triangle.swap", tint: Color(hex: 0xFF9500),
                       title: "Offseason GM playground",
                       detail: "Sign real free agents, build trades against real cap space, and share your moves timeline.")
            featureRow(icon: "sparkles", tint: Theme.Palette.accentAlt,
                       title: "Instant AI article summaries",
                       detail: "Hold any news card for a quick 3-sentence summary — no leaving the app.")
            featureRow(icon: "wand.and.stars", tint: Theme.Palette.accent,
                       title: "First in line",
                       detail: "New Premium tools land here first as the app grows.")
        }
    }

    private func featureRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.14))
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            .strokeBorder(Theme.Palette.border, lineWidth: 1))
    }

    private var subscribeButton: some View {
        PressableButton(action: {
            guard !purchasing else { return }
            purchasing = true
            Task {
                let ok = await premium.purchase()
                purchasing = false
                if ok { dismiss() }
            }
        }) {
            HStack(spacing: 8) {
                if purchasing { ProgressView().tint(.white) }
                Text(purchasing ? "Processing…" : "Subscribe for \(premium.priceLabel)/mo")
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(LinearGradient(colors: [Theme.Palette.accent, Theme.Palette.accentAlt],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(Capsule())
        }
        .overlay(alignment: .bottom) {
            if let err = premium.purchaseError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.negative)
                    .offset(y: 22)
            }
        }
    }

    private var restoreRow: some View {
        Button {
            Task { await premium.restore(); if premium.isPremium { dismiss() } }
        } label: {
            Text("Restore purchases")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
        }
    }

    #if DEBUG
    private var devRow: some View {
        Button {
            premium.debugUnlocked.toggle()
            if premium.isPremium { dismiss() }
        } label: {
            Text(premium.debugUnlocked ? "DEV · Premium unlocked — tap to relock" : "DEV · Unlock without purchase")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Palette.textTertiary)
        }
    }
    #endif

    private var finePrint: some View {
        Text("Billed monthly through the App Store. Auto-renews until cancelled in Settings → Subscriptions.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, Theme.Spacing.lg)
    }
}
