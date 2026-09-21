import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(HomeStore.self) private var home
    @State private var editing: LocalProfile?
    @State private var editorOpen = false
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let profile = profiles.active {
                    HStack(spacing: 12) {
                        PhosphorIcon("UserCircle").iconSize(35).foregroundStyle(
                            NavigationStyle.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).font(.system(size: 18.75, weight: .medium))
                            Text("On this device").font(.system(size: 15)).foregroundStyle(
                                .secondary)
                        }
                        Spacer()
                        Button("Edit") { edit(profile) }.font(.system(size: 15)).frame(
                            minHeight: 56
                        )
                        .accessibilityIdentifier("profile.edit")
                    }
                }
                SettingsGroup("Profiles", symbol: "Users") {
                    ForEach(profiles.profiles) { profile in
                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await home.flush()
                                    await profiles.select(profile.id)
                                }
                            } label: {
                                HStack {
                                    Text(profile.name).font(.system(size: 16.25))
                                    Spacer()

                                }.frame(minHeight: 56).contentShape(Rectangle())
                                    .foregroundStyle(
                                        profile.id == profiles.activeID
                                            ? NavigationStyle.accent : .primary
                                    )
                                    .background(
                                        profile.id == profiles.activeID
                                            ? NavigationStyle.accent.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Switch to \(profile.name)")
                                .accessibilityAddTraits(
                                    profile.id == profiles.activeID ? .isSelected : [])
                            Button {
                                edit(profile)
                            } label: {
                                PhosphorIcon("PencilSimple").iconSize(15).frame(
                                    width: 44, height: 44)
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("Rename \(profile.name)")
                        }
                    }
                    Button {
                        editing = nil
                        draft = ""
                        editorOpen = true
                    } label: {
                        Label("Add profile", phosphor: "Plus").font(.system(size: 16.25)).frame(
                            maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(NavigationStyle.accent)
                }
                Text(
                    "Each profile has its own saved titles, reading activity, and preferences. Installed sources and their settings are shared on this device."
                )
                .font(.system(size: 15)).foregroundStyle(.secondary)
                if let error = profiles.error {
                    Text(error).font(.system(size: 15)).foregroundStyle(.orange)
                }
            }
            .disabled(profiles.busy)
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .tracksNavigationScroll()
        .sheet(isPresented: $editorOpen) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile name").font(.system(size: 15)).foregroundStyle(.secondary)
                    TextField("Name", text: $draft).textContentType(.nickname)
                        .font(.system(size: 18.75)).padding(12)
                        .background(NavigationStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("profile.name")
                    if let error = profiles.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                }.padding(20)
                    .background(NavigationStyle.background)
                    .navigationTitle(editing == nil ? "Add profile" : "Edit profile")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editorOpen = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task {
                                    let saved: Bool
                                    if let editing {
                                        saved = await profiles.rename(editing, name: draft)
                                    } else {
                                        saved = await profiles.add(name: draft)
                                    }
                                    if saved { editorOpen = false }
                                }
                            }.disabled(
                                profiles.busy
                                    || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
            }.presentationDetents([.medium])
        }
    }

    private func edit(_ profile: LocalProfile) {
        editing = profile
        draft = profile.name
        editorOpen = true
    }
}
