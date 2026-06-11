import Foundation

/// M0 placeholder for the M3 StoreKit wiring. The *shape* of the paywall is
/// a product invariant (#8) and is fixed here so nothing else hardcodes it:
/// hard paywall after exactly 3 free conversations; the daily pronunciation
/// drill is free forever and never gated; no accounts, no server.
public enum PaywallPolicy {
    public static let freeConversationCap = 3
    public static let dailyDrillIsAlwaysFree = true
}
