import SwiftUI

/// Fantasy entry point (reached from the Play tab): the user's leagues + create/join.
struct FantasyHomeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var store: FantasyStore?

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            if let store {
                FantasyHomeContent(store: store)
            } else {
                ProgressView().tint(Theme.Palette.accent)
            }
        }
        .navigationTitle("Fantasy")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if store == nil { store = FantasyStore(auth: auth) }
            await store?.loadLeagues()
        }
    }
}

private struct FantasyHomeContent: View {
    @Bindable var store: FantasyStore
    @State private var showingCreate = false
    @State private var showingJoin = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                actions

                NavigationLink { GlobalLeagueView(store: store) } label: { globalRow }
                    .buttonStyle(.plain)

                if store.loadingLeagues && store.leagues.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in LoadingShimmer(height: 84) }
                } else if store.leagues.isEmpty {
                    EmptyStateView(
                        systemImage: "trophy.fill",
                        title: "No leagues yet",
                        message: "Create a private league with friends, or join one with an invite code."
                    )
                    .padding(.top, Theme.Spacing.xl)
                } else {
                    ForEach(Array(store.leagues.enumerated()), id: \.element.id) { index, league in
                        NavigationLink {
                            FantasyLeagueView(store: store, leagueId: league.id)
                        } label: {
                            leagueRow(league)
                        }
                        .buttonStyle(.plain)
                        .staggeredEntrance(index: index)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .refreshable { await store.loadLeagues() }
        .sheet(isPresented: $showingCreate) { CreateLeagueSheet(store: store) }
        .sheet(isPresented: $showingJoin) { JoinLeagueSheet(store: store) }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } }
        )) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            PressableButton(action: { showingCreate = true }) {
                label("Create league", icon: "plus.circle.fill", filled: true)
            }
            PressableButton(action: { showingJoin = true }) {
                label("Join", icon: "person.badge.plus", filled: false)
            }
        }
    }

    private var globalRow: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Global League").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    Text("Open to everyone · pick anyone · cumulative leaderboard").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func label(_ text: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
            Text(text).font(Theme.Font.headline())
        }
        .foregroundStyle(filled ? .white : Theme.Palette.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(filled ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func leagueRow(_ league: FantasyLeagueSummary) -> some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.accent.opacity(0.14)).frame(width: 46, height: 46)
                    Image(systemName: league.isGroup ? "person.3.fill" : "globe")
                        .font(.system(size: 20)).foregroundStyle(Theme.Palette.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(league.name).font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                    Text("\(league.memberCount)/\(league.maxMembers) managers · \(statusLabel(league.status))")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                statusChip(league.status)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "open": return "Open"
        case "drafting": return "Drafting"
        case "active": return "Active"
        case "playoffs": return "Playoffs"
        case "complete": return "Complete"
        default: return s.capitalized
        }
    }

    private func statusChip(_ s: String) -> some View {
        let color: Color = s == "drafting" ? Theme.Palette.moderate : (s == "open" ? Theme.Palette.accent : Theme.Palette.strong)
        return Text(statusLabel(s).uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.14)).clipShape(Capsule())
    }
}

// MARK: - Create

private struct CreateLeagueSheet: View {
    @Bindable var store: FantasyStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var teamName = ""
    @State private var leagueType = "group"
    @State private var maxMembers = 8
    @State private var draftPace: DraftPace = .standard
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("League") {
                    TextField("League name", text: $name)
                    Picker("Type", selection: $leagueType) {
                        Text("Private group").tag("group")
                        Text("Global (open)").tag("global")
                    }
                    if leagueType == "group" {
                        Stepper("Max managers: \(maxMembers)", value: $maxMembers, in: 2...16)
                    }
                }
                Section("Draft format") {
                    Picker("Pace", selection: $draftPace) {
                        ForEach(DraftPace.allCases) { p in
                            Label(p.title, systemImage: p.icon).tag(p)
                        }
                    }
                    Text(draftPace.blurb)
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Section("Your team") {
                    TextField("Team name", text: $teamName)
                }
                Section {
                    Text(leagueType == "group"
                         ? "Private leagues use a unique player pool (no duplicates) and get a mid-season trade deadline."
                         : "The global league lets every manager draft anyone — duplicate players are allowed across teams.")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .navigationTitle("Create league")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || teamName.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func create() {
        saving = true
        Task {
            let created = await store.create(name: name, teamName: teamName, leagueType: leagueType, maxMembers: maxMembers, draftPace: draftPace.rawValue)
            saving = false
            if created != nil { dismiss() }
        }
    }
}

// MARK: - Join

private struct JoinLeagueSheet: View {
    @Bindable var store: FantasyStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var teamName = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite code") {
                    TextField("e.g. A1B2C3", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("Your team") {
                    TextField("Team name", text: $teamName)
                }
            }
            .navigationTitle("Join league")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { join() }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || teamName.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func join() {
        saving = true
        Task {
            let joined = await store.join(inviteCode: code, teamName: teamName)
            saving = false
            if joined != nil { dismiss() }
        }
    }
}
