import CommonCrypto
import CryptoKit
import LocalAuthentication
import Observation
import Security
import SwiftUI

@MainActor @Observable final class AppLockStore {
    private(set) var enabled = false
    private(set) var locked = false
    private(set) var loaded = false
    var biometrics: Bool { didSet { defaults.set(biometrics, forKey: "appLock.biometrics") } }
    var notice: String?
    private let defaults: UserDefaults
    private let account: String
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private weak var previousWindow: UIWindow?
    @ObservationIgnored private var loading: Task<Bool, Never>?
    private struct Credential: Codable { let salt: Data; let digest: Data }
    init(defaults: UserDefaults, scope: String) {
        self.defaults = defaults
        account = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        biometrics = defaults.bool(forKey: "appLock.biometrics")
        // Fail closed until the asynchronous Keychain lookup completes.
        enabled = true
        locked = true
    }
    func load() async {
        guard !loaded else { return }
        if loading == nil {
            let account = account
            loading = Task.detached(priority: .userInitiated) {
                do { return try Self.credential(account: account) != nil }
                catch { return true }
            }
        }
        let exists = await loading!.value
        guard !loaded else { return }
        enabled = exists
        locked = exists
        loaded = true
        loading = nil
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.moku.app.lock", kSecAttrAccount as String: account]
    }
    private func credential() throws -> Credential? {
        try Self.credential(account: account)
    }
    private nonisolated static func credential(account: String) throws -> Credential? {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.moku.app.lock",
            kSecAttrAccount as String: account,
        ]
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        // Without keychain access (unsigned Simulator builds) no PIN can ever have been saved;
        // failing closed here would lock the app with no way to unlock it.
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw LockError.storage }
        return try JSONDecoder().decode(Credential.self, from: data)
    }
    private func digest(_ pin: String, salt: Data) throws -> Data { try Self.digest(pin, salt: salt) }
    /// 100k PBKDF2 rounds take a noticeable moment; unlocking runs this off the main actor.
    private nonisolated static func digest(_ pin: String, salt: Data) throws -> Data {
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
        return record(hash: hash, expected: value.digest)
    }
    private func record(hash: Data, expected: Data) -> Bool {
        let difference = zip(hash, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        if difference == 0 && hash.count == expected.count {
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
    func unlock(pin: String) {
        if Date().timeIntervalSince1970 < defaults.double(forKey: "appLock.retryAt") {
            notice = "Too many attempts. Try again in a minute."
            return
        }
        guard !pin.isEmpty, let value = try? credential() else { return }
        let salt = value.salt
        Task {
            let hash = await Task.detached(priority: .userInitiated) { try? Self.digest(pin, salt: salt) }.value
            guard let hash else { return }
            if record(hash: hash, expected: value.digest) { unlock() }
        }
    }
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
        guard loaded, locked, window == nil,
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
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image("MokuMark").resizable().scaledToFit().frame(width: 52, height: 52)
                .foregroundStyle(NavigationStyle.accent)
                .accessibilityHidden(true)
            Text("Moku is locked").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .multilineTextAlignment(.center).font(.title3.monospacedDigit())
                .padding(.vertical, 12).frame(maxWidth: 220)
                .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GeneralStyle.border))
                .focused($focused)
                .onSubmit(unlock)
                .accessibilityIdentifier("appLock.pin")
            if let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(GeneralStyle.label)
                    .multilineTextAlignment(.center)
            }
            Button("Unlock", action: unlock)
                .font(.headline).foregroundStyle(NavigationStyle.background)
                .frame(maxWidth: 220, minHeight: 48)
                .background(NavigationStyle.accent, in: RoundedRectangle(cornerRadius: 12))
                .buttonStyle(.plain)
                .disabled(pin.isEmpty)
            if model.biometrics {
                Button("Use Face ID / Touch ID") { Task { await model.authenticate() } }
                    .font(.subheadline).foregroundStyle(NavigationStyle.accent).frame(minHeight: 44)
            }
            Spacer()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(GeneralStyle.text)
        .background(NavigationStyle.background.ignoresSafeArea()).themedColorScheme()
        .accessibilityAddTraits(.isModal)
        .task {
            // Desktop prompts Windows Hello straight away; do the same with Face ID.
            if model.biometrics { await model.authenticate() } else { focused = true }
        }
    }

    private func unlock() {
        guard !pin.isEmpty else { return }
        model.unlock(pin: pin)
        pin = ""
    }
}
