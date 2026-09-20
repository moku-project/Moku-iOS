import CommonCrypto
import CryptoKit
import LocalAuthentication
import Observation
import Security
import SwiftUI

@MainActor @Observable final class AppLockStore {
    private(set) var enabled = false
    private(set) var locked = false
    var biometrics: Bool { didSet { defaults.set(biometrics, forKey: "appLock.biometrics") } }
    var notice: String?
    private let defaults: UserDefaults
    private let account: String
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private weak var previousWindow: UIWindow?
    private struct Credential: Codable { let salt: Data; let digest: Data }
    init(defaults: UserDefaults, scope: String) {
        self.defaults = defaults
        account = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        biometrics = defaults.bool(forKey: "appLock.biometrics")
        do { enabled = try credential() != nil } catch { enabled = true }
        locked = enabled
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.moku.app.lock", kSecAttrAccount as String: account]
    }
    private func credential() throws -> Credential? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LockError.storage }
        return try JSONDecoder().decode(Credential.self, from: data)
    }
    private func digest(_ pin: String, salt: Data) throws -> Data {
        let password = Array(pin.utf8)
        var result = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            password.withUnsafeBytes { pinBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pinBytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count, saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000, &result, 32)
            }
        }
        guard status == kCCSuccess else { throw LockError.storage }
        return Data(result)
    }
    func configure(pin: String, currentPIN: String) throws {
        guard pin.count >= 6, pin.count <= 8, pin.allSatisfy(\.isNumber), pin.utf8.allSatisfy({ (48...57).contains($0) }) else { throw LockError.invalidPIN }
        if enabled && !verify(currentPIN) { throw LockError.wrongPIN }
        var salt = Data(count: 32)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw LockError.storage }
        let data = try JSONEncoder().encode(Credential(salt: salt, digest: digest(pin, salt: salt)))
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw LockError.storage }
        } else if update != errSecSuccess { throw LockError.storage }
        enabled = true
        notice = nil
    }
    func disable(pin: String) throws {
        guard verify(pin) else { throw LockError.wrongPIN }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LockError.storage }
        enabled = false
        unlock()
    }
    private func verify(_ pin: String) -> Bool {
        if Date().timeIntervalSince1970 < defaults.double(forKey: "appLock.retryAt") {
            notice = "Too many attempts. Try again in a minute."
            return false
        }
        guard !pin.isEmpty, let value = try? credential(), let hash = try? digest(pin, salt: value.salt) else { return false }
        let difference = zip(hash, value.digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        if difference == 0 && hash.count == value.digest.count {
            defaults.removeObject(forKey: "appLock.attempts")
            defaults.removeObject(forKey: "appLock.retryAt")
            notice = nil
            return true
        }
        let attempts = defaults.integer(forKey: "appLock.attempts") + 1
        defaults.set(attempts, forKey: "appLock.attempts")
        if attempts >= 5 { defaults.set(Date().timeIntervalSince1970 + 60, forKey: "appLock.retryAt") }
        notice = "Incorrect PIN."
        return false
    }
    func unlock(pin: String) { if verify(pin) { unlock() } }
    func authenticate() async {
        guard biometrics, enabled, locked else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            notice = "Biometrics unavailable. Enter your PIN."
            return
        }
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock Moku") { unlock() }
        } catch { notice = "Enter your PIN to unlock." }
    }
    func lock() {
        guard enabled else { return }
        locked = true
        showIfLocked()
    }
    func showIfLocked() {
        guard locked, window == nil,
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: AppLockGate(model: self))
        self.window = window
        window.makeKeyAndVisible()
    }
    private func unlock() {
        locked = false
        notice = nil
        window?.isHidden = true
        window = nil
        previousWindow?.makeKey()
    }
    enum LockError: LocalizedError {
        case invalidPIN, wrongPIN, storage
        var errorDescription: String? {
            switch self {
            case .invalidPIN: "Use a PIN with 6–8 digits."
            case .wrongPIN: "Enter the current PIN."
            case .storage: "Couldn’t access secure storage. Try again."
            }
        }
    }
}

private struct AppLockGate: View {
    @Bindable var model: AppLockStore
    @State private var pin = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Unlock Moku") {
                GeneralRow("PIN", detail: "") { SecureField("PIN", text: $pin).keyboardType(.numberPad).generalInput().frame(width: 150) }
                GeneralRow("App lock", detail: model.notice ?? "") {
                    Button("Unlock") { model.unlock(pin: pin); pin = "" }.buttonStyle(GeneralTextButtonStyle())
                }
                if model.biometrics {
                    Button("Use Face ID / Touch ID") { Task { await model.authenticate() } }.buttonStyle(GeneralTextButtonStyle())
                }
            }
        }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NavigationStyle.background.ignoresSafeArea()).preferredColorScheme(.dark)
            .accessibilityAddTraits(.isModal)
    }
}
