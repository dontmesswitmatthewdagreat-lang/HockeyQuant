import SwiftUI

// The app's modal language: instead of system bottom sheets, small/medium
// content presents as a centered floating card — dimmed blurred backdrop,
// spring scale-in, tap-outside / X / drag-down to dismiss. Built on
// fullScreenCover with a clear background so it layers above the tab bar
// with correct safe areas.

private struct FloatingCardHost<CardContent: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> CardContent

    @State private var shown = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Backdrop: dim + blur whatever is behind the cover.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.25))
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
                .onTapGesture { dismiss() }

            content()
                .frame(maxWidth: 560)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Theme.Palette.surfaceRaised)
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Theme.Palette.border.opacity(0.6), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Theme.Palette.surface)
                            .clipShape(Circle())
                    }
                    .padding(Theme.Spacing.sm)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .scaleEffect(shown ? 1 : 0.92)
                .opacity(shown ? 1 : 0)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            dragOffset = v.translation.height > 0
                                ? v.translation.height
                                : v.translation.height / 6   // resist upward
                        }
                        .onEnded { v in
                            if v.translation.height > 110 { dismiss() }
                            else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15)
                          : .spring(response: 0.38, dampingFraction: 0.82)) {
                shown = true
            }
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .easeIn(duration: 0.12) : .easeIn(duration: 0.16)) {
            shown = false
            dragOffset = 60
        }
        let finish = onDismiss
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            finish()
        }
    }
}

/// Bindings are MainActor-confined in our usage; this wrapper lets them cross
/// the @Sendable closure boundary of `Binding(get:set:)` without warnings.
private struct UncheckedBox<V>: @unchecked Sendable {
    let binding: Binding<V>
}

/// Suppresses the system cover slide (we animate the card ourselves) without
/// touching any other transaction on the presenting view.
private func noSlide<V>(_ binding: Binding<V>) -> Binding<V> {
    let box = UncheckedBox(binding: binding)
    return Binding(
        get: { box.binding.wrappedValue },
        set: { value in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { box.binding.wrappedValue = value }
        }
    )
}

extension View {
    /// Present `content` as a floating card (the app's replacement for small
    /// and medium bottom sheets).
    func floatingCard<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: noSlide(isPresented)) {
            FloatingCardHost(onDismiss: { noSlide(isPresented).wrappedValue = false },
                             content: content)
        }
    }

    /// Item-bound variant, mirroring `.sheet(item:)`.
    func floatingCard<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        fullScreenCover(item: noSlide(item)) { value in
            FloatingCardHost(onDismiss: { noSlide(item).wrappedValue = nil }) {
                content(value)
            }
        }
    }
}
