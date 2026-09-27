import Foundation
import os
import Security

/// Lemon Squeezy store/product the license keys must belong to.
/// Fill these in after creating the product (Lemon Squeezy → Products → the product → IDs).
enum LicenseConfig {
    /// 0 accepts keys from any store (development only); set before shipping.
    static let storeID = 0
    static let productID = 0
    /// Checkout page for the "Buy" buttons.
    static let checkoutURL = URL(string: "https://frugoman.github.io/saytype-site/#buy")!
    static let trialDays = 14
    /// How often an activated key is re-checked online (refunds / disabled keys). Offline is fine.
    static let revalidateEvery: TimeInterval = 7 * 86_400
}

/// Free trial + license key activation through the Lemon Squeezy License API.
/// The license API is public (no secret in the app): https://docs.lemonsqueezy.com/api/license-api
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum State: Equatable {
        case trial(daysLeft: Int)
        case trialExpired
        case licensed(email: String?)
    }

    @Published private(set) var state: State = .trial(daysLeft: LicenseConfig.trialDays)
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    var canUse: Bool {
        if case .trialExpired = state { return false }
        return true
    }

    private let log = Logger(subsystem: "SayType", category: "license")
    private let keychain = Keychain(service: "com.nicolasfrugoni.saytype.license")

    private init() {
        refreshState()
        Task { await revalidateIfNeeded() }
    }

    // MARK: - State

    private var trialStart: Date {
        if let stored = keychain.get("trialStart"), let t = TimeInterval(stored) { return Date(timeIntervalSince1970: t) }
        let now = Date()
        keychain.set(String(now.timeIntervalSince1970), for: "trialStart")
        return now
    }

    private func refreshState() {
        if keychain.get("licenseKey") != nil, keychain.get("instanceID") != nil {
            state = .licensed(email: keychain.get("email"))
            return
        }
        let elapsed = Date().timeIntervalSince(trialStart) / 86_400
        let left = LicenseConfig.trialDays - Int(elapsed.rounded(.down))
        state = left > 0 ? .trial(daysLeft: left) : .trialExpired
    }

    // MARK: - Actions

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let json = try await post("activate", ["license_key": key, "instance_name": Host.current().localizedName ?? "Mac"])
            guard json["activated"] as? Bool == true,
                  let instance = json["instance"] as? [String: Any], let instanceID = instance["id"] as? String else {
                lastError = (json["error"] as? String) ?? "That key couldn't be activated."
                return
            }
            guard belongsToThisProduct(json) else {
                lastError = "That key is for a different product."
                _ = try? await post("deactivate", ["license_key": key, "instance_id": instanceID])
                return
            }
            let meta = json["meta"] as? [String: Any]
            keychain.set(key, for: "licenseKey")
            keychain.set(instanceID, for: "instanceID")
            if let email = meta?["customer_email"] as? String { keychain.set(email, for: "email") }
            keychain.set(String(Date().timeIntervalSince1970), for: "lastValidated")
            log.notice("license activated")
            refreshState()
        } catch {
            lastError = "Couldn't reach the license server. Check your internet connection and try again."
        }
    }

    /// Frees this Mac's activation so the key can be used on another Mac.
    func deactivate() async {
        guard let key = keychain.get("licenseKey"), let instanceID = keychain.get("instanceID") else { return }
        isWorking = true
        defer { isWorking = false }
        _ = try? await post("deactivate", ["license_key": key, "instance_id": instanceID])
        clearLicense()
    }

    private func revalidateIfNeeded() async {
        guard let key = keychain.get("licenseKey"), let instanceID = keychain.get("instanceID") else { return }
        let last = keychain.get("lastValidated").flatMap(TimeInterval.init) ?? 0
        guard Date().timeIntervalSince1970 - last > LicenseConfig.revalidateEvery else { return }
        // Network failures keep the license: people dictate on planes.
        guard let json = try? await post("validate", ["license_key": key, "instance_id": instanceID]) else { return }
        let status = (json["license_key"] as? [String: Any])?["status"] as? String
        if json["valid"] as? Bool == true {
            keychain.set(String(Date().timeIntervalSince1970), for: "lastValidated")
        } else if json["valid"] as? Bool == false {
            // Refunded, disabled, or this Mac's activation was removed from the dashboard.
            log.notice("license no longer valid (\(status ?? "unknown", privacy: .public))")
            clearLicense()
        }
    }

    private func clearLicense() {
        for k in ["licenseKey", "instanceID", "email", "lastValidated"] { keychain.delete(k) }
        refreshState()
    }

    private func belongsToThisProduct(_ json: [String: Any]) -> Bool {
        let meta = json["meta"] as? [String: Any] ?? [:]
        if LicenseConfig.storeID != 0, meta["store_id"] as? Int != LicenseConfig.storeID { return false }
        if LicenseConfig.productID != 0, meta["product_id"] as? Int != LicenseConfig.productID { return false }
        return true
    }

    private func post(_ action: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(action)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        request.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Minimal Keychain wrapper for small strings (survives app reinstalls, unlike UserDefaults).
struct Keychain {
    let service: String

    func get(_ account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        if SecItemUpdate(base(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = base(account)
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete(_ account: String) { SecItemDelete(base(account) as CFDictionary) }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
