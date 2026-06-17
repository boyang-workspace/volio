import SwiftUI

@main
struct VolioApp: App {
    @State private var session = VolioSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
