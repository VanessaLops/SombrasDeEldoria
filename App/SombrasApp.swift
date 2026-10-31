import SwiftUI

@main
struct SombrasApp: App {
    @State private var progress = ProgressStore()

    var body: some Scene {
        WindowGroup {
            RootView(progress: progress)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
