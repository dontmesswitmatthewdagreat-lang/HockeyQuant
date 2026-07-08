import Foundation
import StoreKit

/// HockeyQuant Premium ($0.99/month): gates the Offseason GM playground and
/// AI article summaries. StoreKit 2 — entitlement is re-derived from
/// `Transaction.currentEntitlements` on launch and after every transaction.
@Observable @MainActor
final class PremiumStore {
    static let monthlyProductID = "com.hockeyquant.premium.monthly"

    private(set) var product: Product?
    private(set) var isSubscribed = false
    private(set) var purchaseError: String?

    #if DEBUG
    /// Sim/dev escape hatch: App Store Connect products don't exist yet, so
    /// debug builds can flip Premium from the paywall's developer row.
    var debugUnlocked = UserDefaults.standard.bool(forKey: "premiumDebugUnlocked") {
        didSet { UserDefaults.standard.set(debugUnlocked, forKey: "premiumDebugUnlocked") }
    }
    #endif

    var isPremium: Bool {
        #if DEBUG
        return isSubscribed || debugUnlocked
        #else
        return isSubscribed
        #endif
    }

    var priceLabel: String { product?.displayPrice ?? "$0.99" }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task { await load() }
    }

    func load() async {
        product = try? await Product.products(for: [Self.monthlyProductID]).first
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.monthlyProductID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }

    /// Returns true when the purchase completed and the entitlement is active.
    func purchase() async -> Bool {
        purchaseError = nil
        guard let product else {
            purchaseError = "Subscription not available right now."
            return false
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                    return isSubscribed
                }
                purchaseError = "Purchase could not be verified."
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }
}
