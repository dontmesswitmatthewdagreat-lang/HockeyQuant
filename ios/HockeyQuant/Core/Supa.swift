import Foundation
import Supabase

/// Shared Supabase client. One instance so auth session + database calls all
/// carry the same JWT (RLS applies correctly across the app).
enum Supa {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey
    )
}
