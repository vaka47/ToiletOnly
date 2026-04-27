import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var accessViewModel: AccessViewModel

    init(sessionManager: SessionManager) {
        _accessViewModel = StateObject(wrappedValue: AccessViewModel(sessionManager: sessionManager))
    }

    var body: some View {
        ZStack {
            MainAppView()
                .environmentObject(sessionManager)
                .disabled(!sessionManager.isActive)
                .blur(radius: sessionManager.isActive ? 0 : 6)

            if !sessionManager.isActive {
                LockScreenView(viewModel: accessViewModel)
                    .transition(.opacity)
            }
        }
        .onAppear {
            sessionManager.refresh()
            accessViewModel.cameraController.start()
        }
        .onDisappear {
            accessViewModel.cameraController.stop()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                sessionManager.refresh()
            }
        }
    }
}
