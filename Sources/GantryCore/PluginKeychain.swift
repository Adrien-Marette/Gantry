import Foundation
import Security

/// Stores code-host access tokens as internet-password items in the user's
/// Keychain. Tokens are never written into Gantry's state file, logs, or
/// process arguments.
public enum PluginKeychain {
    private static let descriptionPrefix = "Access token used by an Gantry plugin"

    public static func secret(for plugin: PluginConnection) throws -> String? {
        guard let base = baseQuery(for: plugin) else { return nil }
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                throw PluginKeychainError.invalidStoredValue
            }
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case errSecItemNotFound:
            return nil
        default:
            throw PluginKeychainError.from(status)
        }
    }

    public static func hasKey(for plugin: PluginConnection) -> Bool {
        guard let query = baseQuery(for: plugin) else { return false }
        var attributesQuery = query
        attributesQuery[kSecReturnAttributes as String] = true
        attributesQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributesQuery as CFDictionary, &result)
        return status == errSecSuccess && result != nil
    }

    public static func isSynchronized(for plugin: PluginConnection) -> Bool {
        guard let base = baseQuery(for: plugin) else { return false }
        var query = base
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess && result != nil
    }

    public static func store(_ secret: String, for plugin: PluginConnection) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PluginKeychainError.emptyValue
        }
        guard let baseQuery = baseQuery(for: plugin),
              let data = trimmed.data(using: .utf8) else {
            throw PluginKeychainError.missingPluginReference
        }

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: plugin.keychainLabel,
            kSecAttrDescription as String: "\(descriptionPrefix) — \(plugin.kind.title)"
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PluginKeychainError.from(updateStatus)
        }

        var addAttributes: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: plugin.keychainServer,
            kSecAttrAccount as String: plugin.keychainAccount,
            kSecAttrLabel as String: plugin.keychainLabel,
            kSecAttrDescription as String: "\(descriptionPrefix) — \(plugin.kind.title)",
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeHTTPBasic,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecValueData as String: data
        ]
        var status = SecItemAdd(addAttributes as CFDictionary, nil)
        if status != errSecSuccess {
            addAttributes.removeValue(forKey: kSecAttrSynchronizable as String)
            status = SecItemAdd(addAttributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw PluginKeychainError.from(status)
        }
    }

    public static func deleteKey(for plugin: PluginConnection) throws {
        guard let query = baseQuery(for: plugin) else { return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PluginKeychainError.from(status)
        }
    }

    private static func baseQuery(for plugin: PluginConnection) -> [String: Any]? {
        let server = plugin.keychainServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = plugin.keychainAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty, !account.isEmpty else { return nil }
        return [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }
}

public enum PluginKeychainError: Error, LocalizedError {
    case missingPluginReference
    case emptyValue
    case invalidStoredValue
    case keychain(OSStatus, String)

    static func from(_ status: OSStatus) -> PluginKeychainError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
        return .keychain(status, message)
    }

    public var errorDescription: String? {
        switch self {
        case .missingPluginReference:
            return "This plugin is missing its Keychain reference."
        case .emptyValue:
            return "Enter an access token first."
        case .invalidStoredValue:
            return "The saved Keychain value could not be read."
        case .keychain(let status, let message):
            switch status {
            case errSecUserCanceled:
                return "Keychain access was canceled. Allow Gantry to access its saved access token and try again."
            case errSecInteractionNotAllowed:
                return "The Keychain is locked. Unlock your Mac and try again."
            case errSecAuthFailed:
                return "Keychain authentication failed."
            case errSecMissingEntitlement:
                return "Gantry isn't allowed to save this token in the Keychain. Try rebuilding the app with the provided build script."
            default:
                return "Keychain error \(status): \(message)"
            }
        }
    }
}
