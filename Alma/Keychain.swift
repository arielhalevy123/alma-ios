import Foundation
import Security

/// Minimal Keychain wrapper — the native replacement for `expo-secure-store`.
///
/// Note for anyone migrating a signed-in user from the Expo build: the two do **not**
/// share storage. `expo-secure-store` writes under its own service name, so a user
/// who updates from the RN build to this one is signed out once and has to sign in
/// again. That is expected and is called out in SWIFT_CONVERSION_PLAN.md.
enum Keychain {

    /// Scopes every item to this app. Items are also bound to the app's keychain
    /// access group, so nothing else on the device can read them.
    private static let service = "ai.alma.session"

    /// `kSecAttrAccessibleAfterFirstUnlock` — readable by background work after the
    /// first unlock following a reboot, but never while the device is locked from
    /// cold. `WhenUnlocked` would break any future background refresh; `Always` is
    /// deprecated and weaker. This is the right middle setting for a session token.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlock

    static func set(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]

        // Update in place if it exists, otherwise add. SecItemAdd on an existing
        // item returns errSecDuplicateItem rather than overwriting.
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
