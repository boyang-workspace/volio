import SwiftUI
import SwiftData

@main
struct VolioApp: App {
    @State private var session = VolioSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
        .modelContainer(for: [LocalWork.self, LocalProfile.self, LocalAsset.self, LocalProcessingJob.self])
    }
}
