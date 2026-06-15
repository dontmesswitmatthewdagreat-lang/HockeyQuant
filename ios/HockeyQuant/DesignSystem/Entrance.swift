import SwiftUI

/// Staggered "swipe up one after another" entrance for list items (OwnIt-style).
/// Fades + rises, delayed by item index (capped). Respects Reduce Motion.
struct StaggeredEntrance: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .onAppear {
                guard !reduceMotion, !appeared else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)
                    .delay(min(Double(index) * 0.045, 0.32))) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// Apply a staggered entrance animation based on the item's index.
    func staggeredEntrance(index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }
}
