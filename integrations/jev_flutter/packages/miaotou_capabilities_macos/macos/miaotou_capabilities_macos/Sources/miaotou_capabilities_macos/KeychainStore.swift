import Foundation
import Security

/// The system Keychain, through `Security.framework`.
///
/// **This is the only storage work in the port with no pure-Dart half.**
/// `SecItem*` is C API, and the frozen Python port reached it by running
/// `/usr/bin/security` as a subprocess (the port is preserved by
/// `archive/jev-mac-python-final`). That route is closed here for two reasons,
/// both structural rather than stylistic: the app is sandboxed
/// (`apps/miaotou_app/macos/Runner/Release.entitlements` sets
/// `com.apple.security.app-sandbox`), and `security` is not on a sandboxed app's
/// allowed surface. So the framework is called in-process, and the secret is
/// passed as a `CFString` that never becomes a command line, a log line or a
/// file.
///
/// ## The data protection keychain, and what it costs
///
/// Every query sets `kSecUseDataProtectionKeychain: true`, which is required from
/// macOS 10.15 onward and is the reason the deployment target is well above the
/// podspec's floor for any other reason. Without it the item lives in the
/// file-based login keychain and **every access from a different binary raises an
/// authorisation dialog**; with it, the item lives in the data protection
/// keychain, which is scoped per application and never prompts.
///
/// The honest consequence, which the Dart side repeats in
/// `secrets.dart`: **this is not the same keychain the login-keychain writer used,
/// so a key saved by the previous build is not visible here and has to be entered
/// once more.** There is no code path that hides or works around this.
///
/// The alternative would be a `keychain-access-groups` entitlement naming a shared
/// group, which would let the app find the old items. It is deliberately absent:
/// an access group must be provisioned against a developer **team**, and a build
/// requesting an entitlement the author alone holds fails to sign everywhere
/// else. When a team identifier exists, the one line to add is
/// `kSecAttrAccessGroup` on each query.
///
/// ## The service name
///
/// One fixed `kSecAttrService` for the whole application, with the `SecretStore`
/// key in `kSecAttrAccount`. That split is what makes `keys()` possible: listing
/// by service returns every account this app stored, and the account *is* the
/// key. One service per secret would make the list a scan of names this file
/// invented, which is a second naming scheme to keep in step.
enum KeychainStore {
    /// Shared with the Dart side's `MacosSecretStore`. Asserted by
    /// `secrets_test.dart`, which reads this file.
    static let service = "com.miaotoujunshi.secrets"

    /// The stored secret, or nil when the key is not set.
    static func read(_ key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8) else {
                throw KeychainError.unreadable(key)
            }
            return text
        case errSecItemNotFound:
            // A key that was never set is not an error. The contract says so, and
            // a settings screen asking about a provider the user has not
            // configured is the ordinary case rather than a failure.
            return nil
        default:
            throw KeychainError.status(key, status)
        }
    }

    /// Stores `value` under `key`, replacing whatever was there.
    static func write(_ key: String, value: String) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(key, updateStatus)
        }

        var add = baseQuery(key)
        add[kSecValueData as String] = data
        // The item is readable after the first unlock rather than only while the
        // user is logged in, so a launch agent or a background refresh does not
        // find an empty store for a key the user did enter.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.status(key, addStatus)
        }
    }

    /// Removes `key`. A key that is not set is not an error.
    static func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(key, status)
        }
    }

    /// The **names** of the keys this app has stored, and never their values.
    ///
    /// `kSecReturnData` is absent and `kSecMatchLimitAll` asks for every match.
    /// That combination is the whole privacy property of `SecretStore.keys()`: the
    /// query returns attribute dictionaries, which carry the account and nothing
    /// else, so there is no path by which this function *could* return a secret
    /// even if a caller wanted one. `secrets_test.dart` reads this file and fails
    /// if `kSecReturnData` is ever added to it.
    static func keys() throws -> [String] {
        // Built as a literal rather than by deleting entries off `baseQuery`,
        // so that the absence of a return-data attribute is visible in the code
        // rather than being a statement about what was removed. `secrets_test.dart`
        // reads this function and fails if a data attribute ever appears in it.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw KeychainError.status("<keys>", status)
        }
        guard let rows = result as? [[String: Any]] else {
            return []
        }
        return rows
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .sorted()
    }

    /// The query every call starts from.
    ///
    /// `kSecUseDataProtectionKeychain` is here rather than at each call site so
    /// that a new query cannot forget it — forgetting it does not fail to
    /// compile, it produces an app that prompts the user for every key on every
    /// read.
    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

/// What the Keychain refused, in a form the channel can carry.
///
/// `OSStatus` is an `Int32`, so it crosses to Dart as an integer code rather than
/// a message the user would read: the codes are stable, the strings are not, and
/// a support report quoting `25308` is more use than one quoting a sentence that
/// changes with the wording.
enum KeychainError: Error {
    /// The entry exists but its bytes are not the UTF-8 this app wrote.
    case unreadable(String)

    /// A `SecItem*` call failed. The payload is the `OSStatus`.
    case status(String, OSStatus)

    var code: Int {
        switch self {
        case .unreadable:
            return 1
        case .status(_, let status):
            return Int(status)
        }
    }

    var message: String {
        switch self {
        case .unreadable(let key):
            return "钥匙串中的 \(key) 无法按文本读取"
        case .status(let key, let status):
            return "钥匙串操作失败（\(key)，状态 \(status)）"
        }
    }
}
