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
        SettingsForm {
            Section {
                Toggle("Require a password", isOn: Binding(get: { passwordSet }, set: { value in
                    if !value { removePassword = true }
                }))
                .disabled(!loaded || !passwordSet || busy)
                .accessibilityIdentifier("Require a password")
                SecureField(passwordSet ? "New password" : "Password", text: $password)
                    .textContentType(.newPassword)
                Button(passwordSet ? "Change password" : "Enable password") { Task { await savePassword() } }
                    .disabled(password.isEmpty || busy || !loaded)
            } header: {
                Text("Server password")
            } footer: {
                Text("The app’s private API token remains valid.")
            }
            Section {
                if lock.enabled {
                    SecureField("Current PIN", text: $currentPIN).keyboardType(.numberPad)
                }
                SecureField(lock.enabled ? "New PIN" : "PIN", text: $newPIN).keyboardType(.numberPad)
                Button(lock.enabled ? "Change PIN" : "Enable app lock") {
                    do { try lock.configure(pin: newPIN, currentPIN: currentPIN); newPIN = ""; currentPIN = ""; notice = nil }
                    catch { notice = error.localizedDescription }
                }.disabled(newPIN.isEmpty)
            } header: {
                Text("App lock")
            } footer: {
                Text("6–8 digits, stored in the device Keychain. Locks when Moku goes into the background.")
            }
            if lock.enabled {
                Section {
                    SettingsToggle("Face ID / Touch ID", detail: "Use biometrics as an alternative to the PIN.", isOn: Binding(get: { lock.biometrics }, set: { lock.biometrics = $0 }))
                    Button("Remove app lock", role: .destructive) {
                        do { try lock.disable(pin: currentPIN); currentPIN = ""; notice = nil }
                        catch { notice = error.localizedDescription }
                    }
                } footer: {
                    Text("Removing the app lock requires the current PIN.")
                }
            }
            SettingsNotice(text: notice)
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
