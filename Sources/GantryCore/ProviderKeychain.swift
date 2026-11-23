import Foundation
import Security

/// Stores provider API keys as internet-password items in the user's
/// Keychain. When iCloud Keychain is available, these items are synchronizable
/// so they can appear in Apple Passwords and follow the user across devices.
///
/// Gantry never stores API keys in its session JSON or logs.
public enum ProviderKeychain {
    private static let descriptionPrefix = "API key used by Gantry"

    public static func secret(for provider: AIProvider) throws -> String? {
        guard let base = baseQuery(for: provider) else { return nil }
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                throw ProviderKeychainError.invalidStoredValue
            }
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw ProviderKeychainError.from(status)
        }
    }

    public static func hasKey(for provider: AIProvider) -> Bool {
        guard let query = baseQuery(for: provider) else { return false }
        var attributesQuery = query
        attributesQuery[kSecReturnAttributes as String] = true
        attributesQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributesQuery as CFDictionary, &result)
        return status == errSecSuccess && result != nil
    }

    /// Whether the stored item is currently marked for iCloud Keychain sync.
    /// The store falls back to the local login keychain on systems where the
    /// app isn't entitled to synchronizable items.
    public static func isSynchronized(for provider: AIProvider) -> Bool {
        guard let base = baseQuery(for: provider) else { return false }
        var query = base
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess && result != nil
    }

    public static func store(_ secret: String, for provider: AIProvider) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderKeychainError.emptyValue
        }
        guard let baseQuery = baseQuery(for: provider),
              let data = trimmed.data(using: .utf8) else {
            throw ProviderKeychainError.missingProviderReference
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: provider.keychainLabel,
            kSecAttrDescription as String: "\(descriptionPrefix) — \(provider.name)"
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderKeychainError.from(updateStatus)
        }

        var addAttributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: provider.keychainServer,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecAttrLabel as String: provider.keychainLabel,
            kSecAttrDescription as String: "\(descriptionPrefix) — \(provider.name)",
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeHTTPBasic,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecValueData as String: data
        ]
        var status = SecItemAdd(addAttributes as CFDictionary, nil)
        if status != errSecSuccess {
            // Local ad-hoc builds may not be entitled to iCloud Keychain items.
            // Keep the credential in the local login keychain rather than losing it.
            addAttributes.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemAdd(addAttributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw ProviderKeychainError.from(status)
        }
    }

    public static func deleteKey(for provider: AIProvider) throws {
        guard let query = baseQuery(for: provider) else { return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderKeychainError.from(status)
        }
    }

    private static func baseQuery(for provider: AIProvider) -> [String: Any]? {
        let server = provider.keychainServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = provider.keychainAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !account.isEmpty else { return nil }
        return [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }
}

public enum ProviderKeychainError: Error, LocalizedError {
    case missingProviderReference
    case emptyValue
    case invalidStoredValue
    case keychain(OSStatus, String)

    static func from(_ status: OSStatus) -> ProviderKeychainError {
        let message: String
        if let cfMessage = SecCopyErrorMessageString(status, nil) as String? {
            message = cfMessage
        } else {
            message = "Unknown Keychain error"
        }
        return .keychain(status, message)
    }

    public var errorDescription: String? {
        switch self {
        case .missingProviderReference:
            return "This provider is missing its Keychain reference."
        case .emptyValue:
            return "Enter an API key first."
        case .invalidStoredValue:
            return "The saved Keychain value could not be read."
        case .keychain(let status, let message):
            switch status {
            case errSecUserCanceled:
                return "Keychain access was canceled. Allow Gantry to access its saved API key and try again."
            case errSecInteractionNotAllowed:
                return "The Keychain is locked. Unlock your Mac and try again."
            case errSecAuthFailed:
                return "Keychain authentication failed."
            case errSecMissingEntitlement:
                return "Gantry isn't allowed to save this key in the Keychain. Try rebuilding the app with the provided build script."
            default:
                return "Keychain error \(status): \(message)"
            }
        }
    }
}
