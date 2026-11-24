import Foundation
import Security

/// Where tokens and FRITZ!Box passwords are kept: the Keychain in the apps, memory in tests.
public protocol SecretStore: Sendable {
    func secret(for key: SecretKey) throws -> String?
    /// Stores the secret, or removes it for nil.
    func setSecret(_ secret: String?, for key: SecretKey) throws
}

public enum SecretKey: Hashable, Sendable {
    /// RedhAPI's token for a server.
    case token(server: UUID)
    /// The password of a box's FRITZ!Box user.
    case password(box: UUID)

    public var account: String {
        switch self {
        case .token(let server): "token:\(server.uuidString)"
        case .password(let box): "password:\(box.uuidString)"
        }
    }
}

/// Generic passwords in the Keychain, on this device only. On the iPhone and the Watch they're
/// readable after the first unlock; the Watch gets its copies from the iPhone, not from iCloud.
/// On the Mac they're in the login keychain: the data protection keychain needs a keychain access
/// group, which only a provisioning profile grants, and a free developer account's profiles expire
/// after 7 days.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "com.redhwire.redhcontrol") {
        self.service = service
    }

    public func secret(for key: SecretKey) throws -> String? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func setSecret(_ secret: String?, for key: SecretKey) throws {
        let query = query(for: key)
        guard let secret else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        var attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        #if !os(macOS)
        // The login keychain doesn't support it.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func query(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
        ]
    }
}

public struct KeychainError: Error, Hashable, Sendable, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Secrets in memory, for tests and previews.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [SecretKey: String]

    public init(_ secrets: [SecretKey: String] = [:]) {
        self.secrets = secrets
    }

    public func secret(for key: SecretKey) throws -> String? {
        lock.withLock { secrets[key] }
    }

    public func setSecret(_ secret: String?, for key: SecretKey) throws {
        lock.withLock { secrets[key] = secret }
    }
}
