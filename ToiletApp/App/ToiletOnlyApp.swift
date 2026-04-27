import SwiftUI

@main
struct ToiletOnlyApp: App {
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView(sessionManager: sessionManager)
                .environmentObject(sessionManager)
        }
    }
}
