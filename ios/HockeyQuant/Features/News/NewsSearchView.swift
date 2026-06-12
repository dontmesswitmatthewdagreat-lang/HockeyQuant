import SwiftUI

/// AI news search: live answer with cited sources + matches from past digests.
struct NewsSearchView: View {
    let store: NewsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var result: NewsSearchResponse?
    @State private var searching = false
    @State private var didSearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                VStack(spacing: Theme.Spacing.md) {
                    searchField
                    if searching {
                        Spacer(); ProgressView().tint(Theme.Palette.accent); Spacer()
                    } else if let r = result {
                        results(r)
                    } else {
                        Spacer()
                        EmptyStateView(systemImage: "sparkle.magnifyingglass", title: "Ask about the NHL",
                                       message: "“What's the latest on the Larkin trade?” · “Who did the Kings hire?”")
                        Spacer()
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
            TextField("Ask or search NHL news…", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { runSearch() }
            if !query.isEmpty {
                Button { query = ""; result = nil; didSearch = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.surface).clipShape(Capsule())
    }

    private func results(_ r: NewsSearchResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !r.answer.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles").foregroundStyle(Theme.Palette.accent)
                                Text("ANSWER").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.accent)
                            }
                            Text(r.answer).font(Theme.Font.body()).foregroundStyle(Theme.Palette.textPrimary)
                        }
                    }
                }
                if !r.sources.isEmpty {
                    sectionLabel("SOURCES")
                    ForEach(r.sources) { itemRow($0) }
                }
                if !r.pastMatches.isEmpty {
                    sectionLabel("FROM EARLIER DIGESTS")
                    ForEach(r.pastMatches) { itemRow($0) }
                }
                if r.answer.isEmpty && r.sources.isEmpty && r.pastMatches.isEmpty {
                    Text("No results. Try rephrasing.").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemRow(_ item: DigestItem) -> some View {
        Button { if let u = URL(string: item.url) { openURL(u) } } label: {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.headline).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Text(item.source).font(.system(size: 11)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right.square").font(.system(size: 13)).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        searching = true; didSearch = true
        Task {
            result = await store.search(q)
            searching = false
        }
    }
}
