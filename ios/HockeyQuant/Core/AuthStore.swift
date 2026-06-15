import Foundation
import Observation
import Supabase
import GoogleSignIn
import UIKit

/// Wraps the Supabase client and exposes auth state to the UI.
/// Accounts are shared with the web app (same Supabase project).
/// Only the public anon key lives here — the service key stays server-side.
@MainActor
@Observable
final class AuthStore {

    /// Result of a sign-up attempt, so the UI can give accurate guidance.
    enum SignUpOutcome {
        case signedIn          // session created immediately (confirmation disabled)
        case needsConfirmation // genuinely new email — confirmation email sent
        case alreadyRegistered // email already has an account — should sign in
    }

    /// Google iOS OAuth client ID (public — ships in the app + Info.plist scheme).
    /// Add this same ID to Supabase → Auth → Providers → Google → "Authorized
    /// Client IDs" so Supabase will accept the native ID token.
    static let googleIOSClientID =
        "834695692940-3n835vqo1ohke342ajijcl6216bes5oj.apps.googleusercontent.com"

    private let client = Supa.client

    private(set) var session: Session?
    private(set) var isInitializing = true
    private(set) var username: String?
    private(set) var favoriteTeam: String?
    private(set) var onboardingComplete = false

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user.email }
    var userId: String? { session?.user.id.uuidString }

    private func onboardKey(_ uid: String) -> String { "onboarded_\(uid)" }

    init() {
        Task { await observeAuthChanges() }
    }

    /// Streams auth state changes (initial session, sign in/out, token refresh).
    private func observeAuthChanges() async {
        for await change in client.auth.authStateChanges {
            Log.info("Auth event: \(String(describing: change.event))")
            session = change.session
            if let uid = change.session?.user.id.uuidString {
                onboardingComplete = UserDefaults.standard.bool(forKey: onboardKey(uid))
                await loadProfile()
            } else {
                onboardingComplete = false
                username = nil
                favoriteTeam = nil
            }
            isInitializing = false
        }
    }

    /// Marks first-run onboarding complete for this account (device-local).
    func markOnboarded() {
        guard let uid = userId else { return }
        UserDefaults.standard.set(true, forKey: onboardKey(uid))
        onboardingComplete = true
    }

    /// A fresh (auto-refreshed) access token for authenticating backend calls.
    func accessToken() async -> String? {
        try? await client.auth.session.accessToken
    }

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        let response = try await client.auth.signUp(email: email, password: password)
        if response.session != nil { return .signedIn }
        // Supabase returns an empty `identities` array (and no email) when the
        // address already belongs to an account — it hides this to prevent
        // email enumeration. Surface it as a "sign in instead" hint.
        if response.user.identities?.isEmpty == true { return .alreadyRegistered }
        return .needsConfirmation
    }

    /// Native Google sign-in (no browser bounce, no supabase.co page).
    /// Presents the system Google account sheet, then exchanges the ID token
    /// with Supabase. The user cancelling is treated as a no-op, not an error.
    func signInWithGoogle() async throws {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Self.googleIOSClientID)

        guard let presenter = Self.topViewController() else {
            throw NSError(domain: "HockeyQuant", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't present Google sign-in."
            ])
        }

        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as GIDSignInError where error.code == .canceled {
            return // user dismissed the sheet
        }

        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "HockeyQuant", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Google didn't return an ID token."
            ])
        }
        let accessToken = result.user.accessToken.tokenString

        _ = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .google, idToken: idToken, accessToken: accessToken)
        )
    }

    /// Top-most view controller to present the Google sheet from.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Sign in with Apple. The native flow yields an identity token + the raw
    /// nonce; Supabase verifies them. Requires the Apple provider configured in
    /// Supabase (needs an Apple Developer account).
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        _ = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            Log.error("Sign out failed", error)
        }
    }

    // MARK: - Profile (username shown on the leaderboard)

    private struct ProfileRow: Decodable {
        let username: String?
        let favoriteTeam: String?
        enum CodingKeys: String, CodingKey { case username; case favoriteTeam = "favorite_team" }
    }
    private struct UsernameUpsert: Encodable { let id: String; let username: String }
    private struct TeamUpsert: Encodable {
        let id: String
        let favoriteTeam: String?
        enum CodingKeys: String, CodingKey { case id; case favoriteTeam = "favorite_team" }
    }

    func loadProfile() async {
        guard let uid = session?.user.id else { return }
        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select("username,favorite_team")
                .eq("id", value: uid.uuidString)
                .execute()
                .value
            username = rows.first?.username
            favoriteTeam = rows.first?.favoriteTeam
        } catch {
            Log.error("loadProfile failed", error)
        }
    }

    func updateUsername(_ name: String) async throws {
        guard let uid = session?.user.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client
            .from("profiles")
            .upsert(UsernameUpsert(id: uid.uuidString, username: trimmed), onConflict: "id")
            .execute()
        username = trimmed
    }

    func updateFavoriteTeam(_ abbrev: String?) async {
        guard let uid = session?.user.id else { return }
        do {
            try await client
                .from("profiles")
                .upsert(TeamUpsert(id: uid.uuidString, favoriteTeam: abbrev), onConflict: "id")
                .execute()
            favoriteTeam = abbrev
        } catch {
            Log.error("updateFavoriteTeam failed", error)
        }
    }
}
