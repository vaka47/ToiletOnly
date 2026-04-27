import SwiftUI

@main
struct ToiletOnlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView(sessionManager: sessionManager)
                .environmentObject(sessionManager)
                .environmentObject(authViewModel)
        }
    }
}
