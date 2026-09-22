import SwiftUI

struct AppHostView: View {
    @State private var storage = AppDataStore.makeDefault()
    var body: some View {
        #if DEBUG
            if PreviewMode.isEnabled { AppPreviewHost() } else { appContent }
        #else
            appContent
        #endif
    }

    private var appContent: some View {
        Group {
            if storage.loaded {
                AppSessionView(storage: storage)
            } else {
                VStack(spacing: 16) {
                    if let error = storage.error {
                        Text(error).font(.subheadline)
                        Button("Try again") { Task { await storage.load() } }
                    } else {
                        ContentSkeleton(style: .startup)
                    }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NavigationStyle.background)
            }
        }
        .firstLoadSkeleton(
            "startup", loading: !storage.loaded && storage.error == nil, style: .startup
        )
        .environment(storage)
        .preferredColorScheme(.dark)
        .task {
            await storage.load()
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
