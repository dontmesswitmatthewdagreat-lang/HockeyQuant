import SwiftUI

/// Animated NHL-style draft-lottery reveal for off-season leagues. Picks are revealed
/// from the last slot up to #1 overall for suspense, then it offers to start the
/// prospect draft. Worse prior-season finishers carry better odds (shown per row).
struct LotteryView: View {
    let store: FantasyStore
    let leagueId: String
    var preloaded: LotteryResult? = nil
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var result: LotteryResult?
    @State private var revealed = 0          // how many of reveal[] are shown
    @State private var running = false
    @State private var done = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if let r = result {
                board(r)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ProgressView().tint(Theme.Palette.accent)
                    if running {
                        Text("Drawing the lottery…").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            }
        }
        .navigationTitle("Draft Lottery")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load() async {
        if let p = preloaded { result = p; startReveal(p); return }
        running = true
        do { let r = try await store.runLottery(leagueId); result = r; startReveal(r) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        running = false
    }

    private func startReveal(_ r: LotteryResult) {
        revealed = 0
        Task { @MainActor in
            for _ in r.reveal {
                try? await Task.sleep(nanoseconds: 850_000_000)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { revealed += 1 }
                if revealed >= r.reveal.count { Haptics.success() } else { Haptics.tap() }
            }
            withAnimation { done = true }
        }
    }

    private func isRevealed(_ pick: LotteryPick, in r: LotteryResult) -> Bool {
        guard let idx = r.reveal.firstIndex(where: { $0.memberId == pick.memberId }) else { return false }
        return idx < revealed
    }

    @ViewBuilder private func board(_ r: LotteryResult) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("\(r.order.count) teams · worst finish drew the best odds")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
                    ForEach(r.order) { pick in row(pick, revealed: isRevealed(pick, in: r)) }
                }.padding(Theme.Spacing.md)
            }
            if done {
                PressableButton(action: { onDone(); dismiss() }) {
                    Text("Start the draft").font(Theme.Font.headline()).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .padding(Theme.Spacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if result != nil {
                Button("Skip ahead") { withAnimation { revealed = (result?.reveal.count ?? 0); done = true }; Haptics.success() }
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
    }

    private func row(_ p: LotteryPick, revealed: Bool) -> some View {
        let gold = Color(hex: 0xFFD23F)
        let isTop = p.pick == 1 && revealed
        return HStack(spacing: Theme.Spacing.sm) {
            Text("\(p.pick)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(isTop ? gold : Theme.Palette.textSecondary)
                .frame(width: 34)
            if revealed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.teamName).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    Text("@\(p.username ?? "cpu") · \(String(format: "%.0f", p.odds))% at #1")
                        .font(.system(size: 10)).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                if isTop { Image(systemName: "trophy.fill").foregroundStyle(gold) }
            } else {
                Text("• • •").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textTertiary)
                Spacer()
            }
        }
        .padding(Theme.Spacing.sm)
        .background(isTop ? gold.opacity(0.12) : Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .stroke(isTop ? gold : Theme.Palette.border, lineWidth: isTop ? 1.5 : 1))
        .opacity(revealed ? 1 : 0.55)
    }
}
