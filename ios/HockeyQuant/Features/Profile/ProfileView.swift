import SwiftUI
import AuthenticationServices
import PhotosUI

/// Profile tab: hosts auth (sign in / sign up) when signed out, and account
/// info when signed in. The rest of the app works signed-out — auth only gates
/// user-specific features (picks, models).
struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(AvatarStore.self) private var avatar

    /// When presented as a sheet (from the avatar button), shows a Done button.
    var onDone: (() -> Void)? = nil

    @State private var editingUsername = false
    @State private var usernameDraft = ""
    @State private var photoItem: PhotosPickerItem?
    @AppStorage(DigestNotifier.enabledKey) private var digestEnabled = true
    @AppStorage(DigestNotifier.freqKey) private var digestFreqHours = 12

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundView().ignoresSafeArea()
                if auth.isInitializing {
                    ProgressView()
                } else if auth.isSignedIn {
                    signedIn
                } else {
                    AuthView()
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) }
                }
            }
        }
        .task(id: auth.isSignedIn) {
            if auth.isSignedIn { await auth.loadProfile() }
        }
        .alert("Username", isPresented: $editingUsername) {
            TextField("Username", text: $usernameDraft)
                .textInputAutocapitalization(.never)
            Button("Save") { Task { try? await auth.updateUsername(usernameDraft) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This name is shown on the leaderboard.")
        }
    }

    private var signedIn: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                avatarHeader
                usernameCard
                favoriteTeamCard
                digestNotifyCard
                aboutCard
                PressableButton(action: { Task { await auth.signOut() } }) {
                    Text("Sign out")
                        .font(Theme.Font.headline())
                        .foregroundStyle(Theme.Palette.negative)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Palette.negative.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    avatar.set(img)
                }
            }
        }
    }

    private var avatarHeader: some View {
        // Hoist actor-isolated values into locals so the PhotosPicker label
        // closure captures plain Sendable values.
        let img = avatar.image
        let initial = String((auth.username ?? "").prefix(1)).uppercased()
        let accent = Theme.Palette.accent
        let accentAlt = Theme.Palette.accentAlt
        let ringColor = Theme.Palette.background
        return VStack(spacing: Theme.Spacing.sm) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(image: img, initial: initial, size: 96)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(
                                AngularGradient(colors: [accent, accentAlt, accent], center: .center),
                                lineWidth: 3)
                        )
                    ZStack {
                        Circle().fill(accent).frame(width: 30, height: 30)
                        Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    }
                    .overlay(Circle().stroke(ringColor, lineWidth: 3))
                }
            }
            Text((auth.username?.isEmpty == false) ? auth.username! : "Add a username")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(auth.email ?? "Signed in")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if avatar.image != nil {
                Button("Remove photo") { avatar.clear(); photoItem = nil }
                    .font(Theme.Font.caption())
                    .foregroundStyle(Theme.Palette.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var favoriteTeamCard: some View {
        NavigationLink {
            FavoriteTeamPickerView()
        } label: {
            Card {
                HStack(spacing: Theme.Spacing.sm) {
                    if let team = auth.favoriteTeam, !team.isEmpty {
                        CrestView(abbrev: team, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FAVORITE TEAM")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
                            Text(TeamInfo.lookup(team).name)
                                .font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                        }
                    } else {
                        Image(systemName: "star.circle.fill").font(.system(size: 30)).foregroundStyle(Theme.Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FAVORITE TEAM")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.textTertiary)
                            Text("Tap to choose your team").font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var digestNotifyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Toggle(isOn: $digestEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rapid Digest")
                            .font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                        Text("The day's top stories, as a notification")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .tint(Theme.Palette.accent)
                .onChange(of: digestEnabled) { _, _ in DigestNotifier.reschedule() }

                if digestEnabled {
                    Divider().background(Theme.Palette.border)
                    HStack {
                        Text("Frequency").font(Theme.Font.body()).foregroundStyle(Theme.Palette.textSecondary)
                        Spacer()
                        Menu {
                            ForEach(DigestFrequency.allCases) { f in
                                Button(f.label) { digestFreqHours = f.rawValue; DigestNotifier.reschedule() }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(DigestFrequency(rawValue: digestFreqHours)?.label ?? "Twice a day")
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                            }
                            .font(Theme.Font.body()).foregroundStyle(Theme.Palette.accent)
                        }
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                infoRow("Account", "Synced with HockeyQuant web")
                Divider().background(Theme.Palette.border)
                infoRow("Version", appVersion)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.body()).foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value).font(Theme.Font.body()).foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var usernameCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("USERNAME")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text((auth.username?.isEmpty == false) ? auth.username! : "Not set")
                        .font(Theme.Font.headline())
                        .foregroundStyle((auth.username?.isEmpty == false) ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                }
                Spacer()
                PressableButton(action: {
                    usernameDraft = auth.username ?? ""
                    editingUsername = true
                }) {
                    Text((auth.username?.isEmpty == false) ? "Edit" : "Set")
                        .font(Theme.Font.headline())
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
        }
    }
}

/// Change the favorite team after onboarding. Picking a team saves it to the
/// profile and (when team colors are on) re-themes the app instantly. A toggle
/// lets the user opt out of team theming entirely (back to the brand look).
struct FavoriteTeamPickerView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var saving: String?

    private var teams: [TeamInfo] { TeamInfo.all.values.sorted { $0.name < $1.name } }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 4)

    var body: some View {
        ZStack {
            Theme.backgroundView().ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    Card {
                        Toggle(isOn: Binding(
                            get: { theme.useTeamColors },
                            set: { theme.setTeamColors(enabled: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use team colors")
                                    .font(Theme.Font.headline()).foregroundStyle(Theme.Palette.textPrimary)
                                Text("Theme the whole app with your team's colors")
                                    .font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                        .tint(Theme.Palette.accent)
                    }

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(teams, id: \.abbrev) { team in
                            Button {
                                select(team.abbrev)
                            } label: {
                                VStack(spacing: 6) {
                                    CrestView(abbrev: team.abbrev, size: 52)
                                        .overlay(Circle().stroke(Theme.Palette.accent,
                                                                 lineWidth: auth.favoriteTeam == team.abbrev ? 3 : 0))
                                        .scaleEffect(auth.favoriteTeam == team.abbrev ? 1.08 : 1)
                                        .overlay {
                                            if saving == team.abbrev {
                                                ProgressView().tint(.white)
                                            }
                                        }
                                    Text(team.abbrev)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Theme.Palette.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.spring(response: 0.3), value: auth.favoriteTeam)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .navigationTitle("Favorite Team")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ abbrev: String) {
        guard saving == nil else { return }
        Haptics.tap()
        Task {
            saving = abbrev
            await auth.updateFavoriteTeam(abbrev)
            theme.follow(team: abbrev)   // re-theme instantly (if team colors on)
            saving = nil
            dismiss()
        }
    }
}

/// Email/password auth form with a sign-in / sign-up toggle. Reused by the
/// onboarding Welcome screen.
struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    @Environment(\.colorScheme) private var scheme

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var currentNonce: String?

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isSubmitting
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header

                Card {
                    VStack(spacing: Theme.Spacing.md) {
                        field("Email", text: $email, keyboard: .emailAddress, secure: false)
                        field("Password", text: $password, keyboard: .default, secure: true)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Palette.negative)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let infoMessage {
                            Text(infoMessage)
                                .font(Theme.Font.caption())
                                .foregroundStyle(Theme.Palette.strong)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        submitButton
                        orDivider
                        appleButton
                        googleButton
                    }
                }

                toggle
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(Theme.Font.title())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(isSignUp
                 ? "Make daily picks, build models, and climb the leaderboard."
                 : "Sign in to track your picks and models.")
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.lg)
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(Theme.Font.body())
            .padding(Theme.Spacing.sm)
            .background(Theme.Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .stroke(Theme.Palette.border, lineWidth: 1)
            )
        }
    }

    private var submitButton: some View {
        PressableButton(action: submit) {
            HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSignUp ? "Sign up" : "Sign in")
                    .font(Theme.Font.headline())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(canSubmit ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .disabled(!canSubmit)
        .accessibilityLabel(isSignUp ? "Sign up" : "Sign in")
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue, onRequest: { request in
            let nonce = AppleAuth.randomNonce()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleAuth.sha256(nonce)
        }, onCompletion: handleApple)
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .accessibilityLabel("Sign in with Apple")
    }

    private var orDivider: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Rectangle().fill(Theme.Palette.border).frame(height: 1)
            Text("or").font(Theme.Font.caption()).foregroundStyle(Theme.Palette.textTertiary)
            Rectangle().fill(Theme.Palette.border).frame(height: 1)
        }
    }

    private var googleButton: some View {
        PressableButton(action: signInWithGoogle) {
            HStack(spacing: Theme.Spacing.xs) {
                Image("GoogleLogo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text("Continue with Google")
                    .font(Theme.Font.headline())
            }
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Palette.border, lineWidth: 1)
            )
        }
        .accessibilityLabel("Continue with Google")
    }

    private var toggle: some View {
        PressableButton(action: {
            isSignUp.toggle()
            errorMessage = nil
            infoMessage = nil
        }) {
            Text(isSignUp ? "Already have an account? Sign in"
                          : "New here? Create an account")
                .font(Theme.Font.caption())
                .foregroundStyle(Theme.Palette.accent)
        }
    }

    private func submit() {
        errorMessage = nil
        infoMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                if isSignUp {
                    switch try await auth.signUp(email: email, password: password) {
                    case .signedIn:
                        break // auth state updates the UI
                    case .needsConfirmation:
                        infoMessage = "Check your email to confirm your account, then sign in."
                        isSignUp = false
                    case .alreadyRegistered:
                        isSignUp = false
                        errorMessage = "That email already has an account — sign in instead."
                    }
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                Log.error("Auth failed", error)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Apple sign-in failed. Please try again."
                return
            }
            errorMessage = nil
            infoMessage = nil
            Task {
                do {
                    try await auth.signInWithApple(idToken: token, rawNonce: nonce)
                } catch {
                    Log.error("Apple sign-in failed", error)
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled { return }
            Log.error("Apple authorization failed", error)
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() {
        errorMessage = nil
        infoMessage = nil
        Task {
            do {
                try await auth.signInWithGoogle()
            } catch {
                Log.error("Google sign-in failed", error)
                errorMessage = error.localizedDescription
            }
        }
    }
}
