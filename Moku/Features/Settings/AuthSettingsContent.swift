import SwiftUI

struct AuthSettingsContent: View {
    @Environment(AppLockStore.self) private var lock
    @State private var password = ""
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var passwordSet = false
    @State private var loaded = false
    @State private var busy = false
    @State private var notice: String?
    @State private var removePassword = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GeneralSection("Server password") {
                GeneralRow("Require a password", detail: "The app’s private API token remains valid.") {
                    Toggle("Require a password", isOn: Binding(get: { passwordSet }, set: { value in
                        if !value { removePassword = true }
                    })).toggleStyle(GeneralToggleStyle()).disabled(!loaded || !passwordSet || busy)
                }
                GeneralStyle.divider
                GeneralRow(passwordSet ? "New password" : "Password", detail: "") {
                    SecureField("Password", text: $password).textContentType(.newPassword).generalInput().frame(width: 150)
                }
                GeneralRow("Server access", detail: "") {
                    Button(passwordSet ? "Change" : "Enable") { Task { await savePassword() } }
                        .buttonStyle(GeneralTextButtonStyle()).disabled(password.isEmpty || busy || !loaded)
                }
            }
            GeneralSection("App lock") {
                if lock.enabled {
                    GeneralRow("Current PIN", detail: "") { SecureField("Current PIN", text: $currentPIN).keyboardType(.numberPad).generalInput().frame(width: 150) }
                    GeneralStyle.divider
                }
                GeneralRow(lock.enabled ? "New PIN" : "PIN", detail: "6–8 digits. Stored in the device Keychain.") {
                    SecureField("PIN", text: $newPIN).keyboardType(.numberPad).generalInput().frame(width: 150)
                }
                GeneralRow("App lock", detail: "Locks when Moku goes into the background.") {
                    Button(lock.enabled ? "Change PIN" : "Enable") {
                        do { try lock.configure(pin: newPIN, currentPIN: currentPIN); newPIN = ""; currentPIN = ""; notice = nil }
                        catch { notice = error.localizedDescription }
                    }.buttonStyle(GeneralTextButtonStyle()).disabled(newPIN.isEmpty)
                }
                if lock.enabled {
                    GeneralStyle.divider
                    GeneralRow("Face ID / Touch ID", detail: "Use biometrics as an alternative to the PIN.") {
                        Toggle("Face ID / Touch ID", isOn: Binding(get: { lock.biometrics }, set: { lock.biometrics = $0 })).toggleStyle(GeneralToggleStyle())
                    }
                    GeneralStyle.divider
                    GeneralRow("Remove app lock", detail: "Requires the current PIN.") {
                        Button("Disable") {
                            do { try lock.disable(pin: currentPIN); currentPIN = ""; notice = nil }
                            catch { notice = error.localizedDescription }
                        }.buttonStyle(GeneralTextButtonStyle())
                    }
                }
            }
            if let notice { Text(notice).font(.system(size: 13)).foregroundStyle(GeneralStyle.faint) }
        }.task { await load() }
            .confirmationDialog("Remove the server password?", isPresented: $removePassword, titleVisibility: .visible) {
                Button("Remove password", role: .destructive) { Task { await disablePassword() } }
            }
    }
    private func load() async {
        do {
            struct Status: Decodable, Sendable { let passwordSet: Bool }
            struct Result: Decodable, Sendable { let authStatus: Status }
            let result: Result = try await BackendAPI.shared.graphql("{ authStatus { passwordSet } }", requiresSourceRuntime: false)
            passwordSet = result.authStatus.passwordSet
            loaded = true
        } catch { notice = "Couldn’t read server authentication status." }
    }
    private func savePassword() async {
        busy = true
        defer { busy = false }
        do {
            let _: [String: Bool] = try await BackendAPI.shared.graphql("mutation { setPassword(newPassword: \(BackendAPI.literal(password))) }", requiresSourceRuntime: false)
            password = ""
            passwordSet = true
            notice = nil
        } catch { notice = "Couldn’t save the server password." }
    }
    private func disablePassword() async {
        busy = true
        defer { busy = false }
        do {
            let _: [String: Bool] = try await BackendAPI.shared.graphql("mutation { disableServerAuth }", requiresSourceRuntime: false)
            passwordSet = false
            notice = nil
        } catch { notice = "Couldn’t remove the server password." }
    }
}
