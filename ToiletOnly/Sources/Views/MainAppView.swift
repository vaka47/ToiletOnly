import SwiftUI

struct MainAppView: View {
    enum AppTab: String {
        case feed
        case chats
        case videos
        case profile
    }

    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var authViewModel: AuthViewModel
    @AppStorage("debug_overlay") private var showDebugOverlay: Bool = true
    @StateObject private var datingViewModel = DatingViewModel()
    @StateObject private var locationService = LocationService()
    @StateObject private var recorder = VideoRecorder()
    @State private var selectedTab: AppTab = .feed
    @State private var didSendLocationForSession: Bool = false
    @State private var wasSessionActive: Bool = false
    @State private var activityBadgeCount: Int = 0
    @State private var chatBadgeCount: Int = 0
    @State private var showActivitySheet: Bool = false
    @State private var showVideoRecorder: Bool = false

    var body: some View {
        ZStack {
            AppBackground()

            currentTabView
                .padding(.top, 6)
        }
        .background(AppBackground().ignoresSafeArea())
        .safeAreaInset(edge: .top) {
            TopChromeBar(
                expiresAt: sessionManager.expiresAt,
                activityBadgeCount: activityBadgeCount,
                onOpenActivity: {
                    showActivitySheet = true
                    activityBadgeCount = 0
                },
                onOpenRecorder: {
                    showVideoRecorder = true
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            BottomNavigationBar(
                selectedTab: $selectedTab,
                chatBadgeCount: chatBadgeCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.clear)
        }
        .sheet(isPresented: $showActivitySheet, onDismiss: {
            Task { await refreshBadges() }
        }) {
            ActivityView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showVideoRecorder, onDismiss: {
            Task { await refreshBadges() }
        }) {
            VideoRecorderView(recorder: recorder, token: authViewModel.token())
        }
        .overlay(alignment: .center) {
            if !authViewModel.isAuthenticated {
                AuthView(viewModel: authViewModel)
                    .background(Color.black.opacity(0.4).ignoresSafeArea())
            }
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            Toggle(L10n.text("Показывать отладочный оверлей", "Show debug overlay"), isOn: $showDebugOverlay)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        #endif
        .onChange(of: sessionManager.isActive) { isActive in
            Task {
                await ProfileService.shared.updateSessionState(token: authViewModel.token(), active: isActive)
            }
            if isActive {
                if !wasSessionActive {
                    datingViewModel.consumeSessionForPendingMatches()
                }
                sendLocationIfNeeded()
            } else {
                didSendLocationForSession = false
            }
            wasSessionActive = isActive
        }
        .onChange(of: selectedTab) { tab in
            if tab == .chats {
                chatBadgeCount = 0
            }
            Task { await refreshBadges() }
        }
        .onAppear {
            wasSessionActive = sessionManager.isActive
            Task {
                await ProfileService.shared.updateSessionState(token: authViewModel.token(), active: sessionManager.isActive)
                await refreshBadges()
            }
            if sessionManager.isActive {
                sendLocationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var currentTabView: some View {
        switch selectedTab {
        case .feed:
            LiveDatingView(viewModel: datingViewModel)
        case .chats:
            ChatsView()
        case .videos:
            VideoFeedView(viewModel: datingViewModel)
        case .profile:
            ProfileView()
        }
    }

    private func sendLocationIfNeeded() {
        guard !didSendLocationForSession else { return }
        guard authViewModel.isAuthenticated else { return }
        didSendLocationForSession = true
        locationService.requestOneTimeLocation { location in
            guard let location else { return }
            Task {
                await ProfileService.shared.updateLocation(
                    token: authViewModel.token(),
                    lat: location.coordinate.latitude,
                    lon: location.coordinate.longitude
                )
            }
        }
    }

    private func refreshBadges() async {
        async let activityItems = ActivityService.shared.feed(token: authViewModel.token(), limit: 30)
        async let incomingLikes = LikeService.shared.incoming(token: authViewModel.token())
        async let matches = MatchService.shared.list(token: authViewModel.token())
        let activity = await activityItems
        let likes = await incomingLikes
        let matchItems = await matches
        if selectedTab != .chats {
            chatBadgeCount = likes.count + matchItems.filter { !$0.my_is_kept || !$0.other_is_kept }.count
        }
        activityBadgeCount = activity.count
    }
}

private struct TopChromeBar: View {
    let expiresAt: Date?
    let activityBadgeCount: Int
    let onOpenActivity: () -> Void
    let onOpenRecorder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Toilet Dating", "Toilet Dating"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.ink)
                    Text(L10n.text("Live session social", "Live session social"))
                        .font(.caption2)
                        .foregroundColor(AppTheme.muted)
                }
            }

            Spacer()

            SessionChip(expiresAt: expiresAt)

            TopIconButton(icon: "video.badge.plus") {
                onOpenRecorder()
            }

            TopIconButton(icon: "heart.fill", badge: activityBadgeCount) {
                onOpenActivity()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.84))
                .shadow(color: AppTheme.shadow, radius: 16, x: 0, y: 10)
        )
    }
}

private struct BottomNavigationBar: View {
    @Binding var selectedTab: MainAppView.AppTab
    let chatBadgeCount: Int

    var body: some View {
        HStack(spacing: 10) {
            tabButton(.feed, title: L10n.text("Анкеты", "Profiles"), icon: "flame.fill")
            tabButton(.chats, title: L10n.text("Диалоги", "Chats"), icon: "bubble.left.and.bubble.right.fill", badge: chatBadgeCount)
            tabButton(.videos, title: L10n.text("Видео", "Videos"), icon: "play.rectangle.fill")
            tabButton(.profile, title: L10n.text("Профиль", "Profile"), icon: "person.crop.circle.fill")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .shadow(color: AppTheme.shadow, radius: 18, x: 0, y: 10)
        )
    }

    private func tabButton(_ tab: MainAppView.AppTab, title: String, icon: String, badge: Int = 0) -> some View {
        Button {
            selectedTab = tab
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(selectedTab == tab ? AppTheme.accentGradient : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                )
                .foregroundColor(selectedTab == tab ? .white : AppTheme.ink)

                if badge > 0 {
                    Text("\(min(99, badge))")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.coral)
                        .clipShape(Capsule())
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SessionChip: View {
    let expiresAt: Date?

    var body: some View {
        if let expiresAt = expiresAt {
            SessionCountdownPill(expiresAt: expiresAt, accent: AppTheme.mint)
        } else {
            Text(L10n.text("Оффлайн", "Offline"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.coral.opacity(0.14))
                .foregroundColor(AppTheme.coral)
                .clipShape(Capsule())
        }
    }
}

private struct TopIconButton: View {
    let icon: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.86))
                    .clipShape(Circle())
                if badge > 0 {
                    Text("\(min(99, badge))")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.coral)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
