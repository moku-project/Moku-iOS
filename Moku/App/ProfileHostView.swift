import SwiftUI

struct ProfileHostView: View {
    @State private var profiles = ProfileStore.makeDefault()
    var body: some View {
        Group {
            if profiles.loaded {
                ProfileSessionView(profiles: profiles, profileID: profiles.activeID)
                    .id(profiles.activeID)
            } else {
                VStack(spacing: 16) {
                    if let error = profiles.error {
                        Text(error).font(.subheadline)
                        Button("Try again") { Task { await profiles.load() } }
                    } else {
                        ContentSkeleton(style: .startup)
                    }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background)
            }
        }
        .firstLoadSkeleton(
            "startup", loading: !profiles.loaded && profiles.error == nil, style: .startup
        )
        .environment(profiles)
        .preferredColorScheme(.dark)
        .task {
            await profiles.load()
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-start-runtime"),
                    ProcessInfo.processInfo.arguments.contains("--ui-testing-isolated-backend")
                {
                    _ = try? await Backend.shared.connection()
                }
            #endif
        }
    }
}
