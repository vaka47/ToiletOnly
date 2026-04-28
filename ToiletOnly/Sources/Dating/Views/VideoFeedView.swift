import SwiftUI
import AVKit

struct VideoFeedView: View {
    @ObservedObject var viewModel: DatingViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var recorder = VideoRecorder()
    @AppStorage("hidden_video_ids_v1") private var hiddenVideoIDsStorage: String = ""

    @State private var items: [VideoDTO] = []
    @State private var showFilters: Bool = false
    @State private var targetGender: String = "any"
    @State private var minAge: Double = 18
    @State private var maxAge: Double = 50
    @State private var radiusKm: Double = 50
    @State private var sortBy: String = "popular"
    @State private var selectedVideo: VideoDTO?
    @State private var showRecorder: Bool = false
    @State private var showSessionRequiredAlert: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if showFilters {
                        filters
                    }

                    if visibleItems.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(visibleItems) { video in
                                VideoGridCard(video: video) {
                                    selectedVideo = video
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 140)
            }

            Button {
                openRecorderIfAllowed()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 70, height: 70)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: AppTheme.coral.opacity(0.34), radius: 18, x: 0, y: 12)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 22)
            .padding(.bottom, 106)
        }
        .fullScreenCover(item: $selectedVideo) { video in
            ReelVideoPlayer(
                video: video,
                remainingSuperLikes: viewModel.remainingSuperLikesToday,
                onClose: {
                    selectedVideo = nil
                },
                onReact: {
                    Task {
                        await VideoService.shared.react(videoId: video.id, emoji: "❤️", token: authViewModel.token())
                        await reload()
                    }
                },
                onHideVideo: {
                    hide(videoId: video.id)
                    selectedVideo = nil
                },
                onBlockUser: {
                    Task {
                        await BlockService.shared.block(userId: video.user_id, token: authViewModel.token())
                        hideVideos(for: video.user_id)
                        selectedVideo = nil
                    }
                },
                onReportUser: { reason in
                    Task {
                        await ReportService.shared.report(
                            targetUserId: video.user_id,
                            type: "video",
                            reason: reason,
                            token: authViewModel.token()
                        )
                    }
                },
                onSkipProfile: {
                    Task {
                        await viewModel.pass(profile: profileSummary(for: video), token: authViewModel.token())
                        hide(videoId: video.id)
                        selectedVideo = nil
                    }
                },
                onLikeProfile: {
                    Task {
                        _ = await viewModel.like(profile: profileSummary(for: video), token: authViewModel.token())
                        hide(videoId: video.id)
                        selectedVideo = nil
                    }
                },
                onSuperLikeProfile: { message in
                    Task {
                        _ = await viewModel.superLike(
                            profile: profileSummary(for: video),
                            token: authViewModel.token(),
                            message: message
                        )
                        hide(videoId: video.id)
                        selectedVideo = nil
                    }
                }
            )
            .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showRecorder, onDismiss: {
            Task { await reload() }
        }) {
            VideoRecorderView(recorder: recorder, token: authViewModel.token())
        }
        .alert(L10n.text("Нужна активная сессия", "Active session required"), isPresented: $showSessionRequiredAlert) {
            Button(L10n.text("Ок", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.text("Снять и выложить видео можно только пока туалетная сессия еще активна.", "You can record and publish videos only while the toilet session is still active."))
        }
        .task {
            await reload()
        }
        .onChange(of: targetGender) { _ in Task { await reload() } }
        .onChange(of: minAge) { _ in Task { await reload() } }
        .onChange(of: maxAge) { _ in Task { await reload() } }
        .onChange(of: radiusKm) { _ in Task { await reload() } }
        .onChange(of: sortBy) { _ in Task { await reload() } }
    }

    private var visibleItems: [VideoDTO] {
        items.filter { !hiddenVideoIDs.contains($0.id) }
    }

    private var hiddenVideoIDs: Set<String> {
        Set(hiddenVideoIDsStorage.split(separator: ",").map(String.init))
    }

    private var header: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("Видео", "Videos"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.ink)
                        Text(
                            L10n.text(
                                "Лента активных сессий рядом. Открываешь ролик и уже оттуда решаешь: смотреть, лайкать видео или идти в мэтч.",
                                "A feed of active nearby sessions. Open a clip and decide whether to watch, react, or turn it into a match."
                            )
                        )
                        .font(.callout)
                        .foregroundColor(AppTheme.muted)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 10) {
                        iconButton("slider.horizontal.3") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                showFilters.toggle()
                            }
                        }
                        iconButton("arrow.clockwise") {
                            Task { await reload() }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        filterChip(
                            title: targetGender == "any" ? L10n.text("Любой гендер", "Any gender") : localizedGender(targetGender),
                            tint: AppTheme.sky
                        )
                        filterChip(
                            title: L10n.text("\(Int(minAge))-\(Int(maxAge)) лет", "\(Int(minAge))-\(Int(maxAge)) years"),
                            tint: AppTheme.mint
                        )
                        filterChip(
                            title: L10n.text("Радиус \(Int(radiusKm)) км", "Radius \(Int(radiusKm)) km"),
                            tint: AppTheme.coral
                        )
                        filterChip(
                            title: localizedSort(sortBy),
                            tint: AppTheme.mango
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var filters: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("Фильтр видео", "Video filter"))
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)

                Picker("Пол", selection: $targetGender) {
                    Text(L10n.text("Все", "All")).tag("any")
                    Text(L10n.text("Мужчины", "Men")).tag("male")
                    Text(L10n.text("Женщины", "Women")).tag("female")
                    Text(L10n.text("Другое", "Other")).tag("other")
                }
                .pickerStyle(.segmented)

                Picker("sort", selection: $sortBy) {
                    Text(L10n.text("Популярные", "Popular")).tag("popular")
                    Text(L10n.text("Ближайшие", "Nearest")).tag("distance")
                    Text(L10n.text("Новые", "Newest")).tag("recent")
                }
                .pickerStyle(.segmented)

                sliderRow(
                    title: L10n.text("Возраст \(Int(minAge))-\(Int(maxAge))", "Age \(Int(minAge))-\(Int(maxAge))"),
                    leftValue: $minAge,
                    rightValue: $maxAge
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Радиус \(Int(radiusKm)) км", "Radius \(Int(radiusKm)) km"))
                        .font(.subheadline.weight(.semibold))
                    Slider(value: $radiusKm, in: 1...200, step: 1)
                        .tint(AppTheme.sky)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(AppTheme.sky)
                Text(L10n.text("Пока нет подходящих видео", "No matching videos yet"))
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                Text(
                    L10n.text(
                        "Попробуй расширить радиус, сменить фильтр или просто вернись через пару минут, когда кто-то еще зайдет в сессию.",
                        "Try widening the radius, changing filters, or come back in a few minutes when more users enter a session."
                    )
                )
                .font(.subheadline)
                .foregroundColor(AppTheme.muted)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.74))
                .background(.ultraThinMaterial, in: Circle())
                .foregroundColor(AppTheme.ink)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func filterChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func sliderRow(title: String, leftValue: Binding<Double>, rightValue: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Slider(value: Binding(
                get: { leftValue.wrappedValue },
                set: { leftValue.wrappedValue = min($0, rightValue.wrappedValue - 1) }
            ), in: 18...60, step: 1)
            .tint(AppTheme.coral)
            Slider(value: Binding(
                get: { rightValue.wrappedValue },
                set: { rightValue.wrappedValue = max($0, leftValue.wrappedValue + 1) }
            ), in: 19...60, step: 1)
            .tint(AppTheme.mint)
        }
    }

    private func reload() async {
        items = await VideoService.shared.feed(
            token: authViewModel.token(),
            targetGender: targetGender,
            ageMin: Int(minAge),
            ageMax: Int(maxAge),
            sortBy: sortBy,
            radiusKm: radiusKm
        )
    }

    private func openRecorderIfAllowed() {
        guard sessionManager.isActive else {
            showSessionRequiredAlert = true
            return
        }
        showRecorder = true
    }

    private func profileSummary(for video: VideoDTO) -> DatingProfile {
        DatingProfile(
            id: UUID(uuidString: video.user_id) ?? UUID(),
            remoteUserId: video.user_id,
            name: video.display_name,
            age: video.age,
            hideAge: video.hide_age,
            gender: video.gender,
            bio: video.caption,
            photos: [],
            sessionVideoURL: video.asset_url,
            toiletSelfieIndex: 0,
            tags: [],
            isOnline: parseDate(video.session_expires_at) != nil,
            distanceKm: video.distance_km,
            sessionExpiresAt: parseDate(video.session_expires_at)
        )
    }

    private func hide(videoId: String) {
        var ids = hiddenVideoIDs
        ids.insert(videoId)
        hiddenVideoIDsStorage = ids.sorted().joined(separator: ",")
        items.removeAll { $0.id == videoId }
    }

    private func hideVideos(for userId: String) {
        let idsToHide = items.filter { $0.user_id == userId }.map(\.id)
        var ids = hiddenVideoIDs
        ids.formUnion(idsToHide)
        hiddenVideoIDsStorage = ids.sorted().joined(separator: ",")
        items.removeAll { $0.user_id == userId }
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func localizedGender(_ raw: String) -> String {
        switch raw {
        case "male":
            return L10n.text("Мужчины", "Men")
        case "female":
            return L10n.text("Женщины", "Women")
        case "other":
            return L10n.text("Другое", "Other")
        default:
            return L10n.text("Любой гендер", "Any gender")
        }
    }

    private func localizedSort(_ raw: String) -> String {
        switch raw {
        case "distance":
            return L10n.text("Сначала ближе", "Nearest first")
        case "recent":
            return L10n.text("Сначала новые", "Newest first")
        default:
            return L10n.text("Сначала популярные", "Popular first")
        }
    }
}

private struct VideoGridCard: View {
    let video: VideoDTO
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let url = URL(string: video.asset_url) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .allowsHitTesting(false)
                        .frame(height: 274)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [AppTheme.sky.opacity(0.48), AppTheme.coral.opacity(0.38)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        if video.viewer_can_match_author {
                            videoTag(L10n.text("Открыт мэтч", "Match open"))
                        }
                        Spacer()
                        SessionCountdownPill(
                            expiresAt: parseDate(video.session_expires_at),
                            accent: .white
                        )
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if let distance = video.distance_km {
                            videoTag(String(format: L10n.text("%.1f км", "%.1f km"), distance))
                        }
                        videoTag("❤️ \(video.reactions_count)")
                    }

                    Text(video.hide_age ? video.display_name : "\(video.display_name), \(video.age)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !video.caption.isEmpty {
                        Text(video.caption)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(3)
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 274)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: AppTheme.shadow.opacity(0.9), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func videoTag(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct ReelVideoPlayer: View {
    let video: VideoDTO
    let remainingSuperLikes: Int
    let onClose: () -> Void
    let onReact: () -> Void
    let onHideVideo: () -> Void
    let onBlockUser: () -> Void
    let onReportUser: (String) -> Void
    let onSkipProfile: () -> Void
    let onLikeProfile: () -> Void
    let onSuperLikeProfile: (String) -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showComments: Bool = false
    @State private var showActions: Bool = false
    @State private var showReportComposer: Bool = false
    @State private var reportReason: String = ""
    @State private var showFullCaption: Bool = false
    @State private var showSuperLikeComposer: Bool = false
    @State private var superLikeMessage: String = ""
    @State private var selectedProfile: DatingProfile?
    @State private var isFollowing: Bool = false
    @State private var isUpdatingFollow: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: video.asset_url) {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button {
                        Task { await loadProfile() }
                    } label: {
                        HStack(spacing: 10) {
                            AsyncAvatarView(urlString: nil, fallback: video.display_name)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(video.hide_age ? video.display_name : "\(video.display_name), \(video.age)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text(L10n.text("Открыть профиль", "Open profile"))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.72))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    SessionCountdownPill(expiresAt: parseDate(video.session_expires_at), accent: .white)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()

                HStack(alignment: .bottom, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Button {
                            Task { await toggleFollow() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isFollowing ? "bell.badge.fill" : "plus.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text(isFollowing ? L10n.text("Уведомления включены", "Live alerts on") : L10n.text("Подписаться", "Follow"))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(isFollowing ? AppTheme.actionGradient : AppTheme.accentGradient)
                            )
                        }
                        .buttonStyle(.plain)
                        .opacity(isUpdatingFollow ? 0.68 : 1)
                        .disabled(isUpdatingFollow)

                        if !video.caption.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    showFullCaption.toggle()
                                }
                            } label: {
                                Text(video.caption)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(showFullCaption ? nil : 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }

                        if video.viewer_can_match_author {
                            HStack(spacing: 16) {
                                profileActionButton(icon: "xmark", tint: .white, fill: Color.white.opacity(0.16), action: onSkipProfile)
                                profileActionButton(icon: "heart.fill", tint: AppTheme.mango, fill: AppTheme.mango.opacity(0.20)) {
                                    showSuperLikeComposer = true
                                }
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(remainingSuperLikes)")
                                            .font(.caption2.bold())
                                            .foregroundColor(AppTheme.ink)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(Color.white)
                                            .clipShape(Capsule())
                                            .offset(x: 4, y: -4)
                                    }
                                profileActionButton(icon: "heart.fill", tint: .white, fill: AppTheme.coral, action: onLikeProfile)
                            }
                        }
                    }

                    Spacer()

                    VStack(spacing: 18) {
                        railButton(icon: "heart.fill", title: "\(video.reactions_count)", action: onReact)
                        railButton(icon: "bubble.right.fill", title: "\(video.comments_count)") {
                            showComments = true
                        }
                        railButton(icon: "ellipsis", title: "") {
                            showActions = true
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showComments) {
            VideoCommentsStandalone(video: video)
                .environmentObject(authViewModel)
        }
        .onAppear {
            isFollowing = video.viewer_follows_author
        }
        .sheet(item: $selectedProfile) { profile in
            ProfileInfoView(profile: profile)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showSuperLikeComposer) {
            SuperLikeComposerSheet(
                title: video.hide_age ? video.display_name : "\(video.display_name), \(video.age)",
                remaining: remainingSuperLikes,
                message: $superLikeMessage,
                onCancel: {
                    superLikeMessage = ""
                    showSuperLikeComposer = false
                },
                onSend: {
                    onSuperLikeProfile(superLikeMessage)
                    superLikeMessage = ""
                    showSuperLikeComposer = false
                }
            )
        }
        .sheet(isPresented: $showReportComposer) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("Почему жалоба?", "Why are you reporting it?"))
                        .font(.headline)
                    TextEditor(text: $reportReason)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 160)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppTheme.cream)
                        )
                    Spacer()
                }
                .padding(20)
                .navigationTitle(L10n.text("Пожаловаться", "Report"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.text("Отмена", "Cancel")) {
                            showReportComposer = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.text("Отправить", "Send")) {
                            onReportUser(reportReason.trimmingCharacters(in: .whitespacesAndNewlines))
                            reportReason = ""
                            showReportComposer = false
                        }
                    }
                }
            }
        }
        .confirmationDialog(L10n.text("Действия с видео", "Video actions"), isPresented: $showActions, titleVisibility: .visible) {
            Button(L10n.text("Не показывать больше", "Hide this video")) {
                onHideVideo()
            }
            Button(L10n.text("Пожаловаться", "Report")) {
                showReportComposer = true
            }
            Button(L10n.text("Заблокировать автора", "Block author"), role: .destructive) {
                onBlockUser()
            }
            Button(L10n.text("Отмена", "Cancel"), role: .cancel) {}
        }
    }

    private func railButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
                if !title.isEmpty {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.92))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func profileActionButton(icon: String, tint: Color, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
                .background(fill)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func loadProfile() async {
        guard let dto = await ProfileService.shared.fetchProfile(userId: video.user_id, token: authViewModel.token()) else { return }
        selectedProfile = DatingProfile(
            id: UUID(uuidString: dto.user_id) ?? UUID(),
            remoteUserId: dto.user_id,
            name: dto.display_name,
            age: dto.age,
            hideAge: dto.hide_age,
            gender: dto.gender,
            bio: dto.bio_text.isEmpty ? dto.bio_ai : dto.bio_text,
            photos: [dto.toilet_selfie_url] + dto.photos,
            sessionVideoURL: dto.session_video_url,
            toiletSelfieIndex: 0,
            tags: dto.interests,
            isOnline: dto.session_expires_at != nil,
            distanceKm: video.distance_km,
            sessionExpiresAt: parseDate(dto.session_expires_at)
        )
    }

    private func toggleFollow() async {
        isUpdatingFollow = true
        let nextValue = !isFollowing
        let result = await VideoService.shared.setFollowing(
            userId: video.user_id,
            isFollowing: nextValue,
            token: authViewModel.token()
        )
        isFollowing = result
        isUpdatingFollow = false
    }
}

private struct SuperLikeComposerSheet: View {
    let title: String
    let remaining: Int
    @Binding var message: String
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L10n.text("Суперлайк", "Super like"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Spacer()
                    Text(
                        L10n.text(
                            "Осталось сегодня: \(remaining)",
                            "Left today: \(remaining)"
                        )
                    )
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.mango.opacity(0.22))
                    .clipShape(Capsule())
                }

                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)

                Text(
                    L10n.text(
                        "Сразу добавь короткое сообщение. Его увидят до мэтча, и это заметно поднимает шанс ответа.",
                        "Add a short note right away. They will see it before the match, which significantly improves reply rate."
                    )
                )
                .font(.subheadline)
                .foregroundColor(AppTheme.muted)

                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppTheme.cream)
                    )
                    .onChange(of: message) { value in
                        if value.count > 240 {
                            message = String(value.prefix(240))
                        }
                    }

                Spacer()

                Button(action: onSend) {
                    Text(L10n.text("Отправить суперлайк", "Send super like"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(tint: AppTheme.mango))
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.text("Закрыть", "Close"), action: onCancel)
                }
            }
        }
    }
}

private struct VideoCommentsStandalone: View {
    let video: VideoDTO
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [VideoCommentDTO] = []
    @State private var text: String = ""
    @State private var replyingTo: VideoCommentDTO?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(comment.display_name)
                                .font(.caption.bold())
                            Text(comment.deleted ? L10n.text("Комментарий удален", "Comment deleted") : comment.text)
                                .foregroundColor(comment.deleted ? .secondary : .primary)
                            if !comment.deleted {
                                HStack(spacing: 12) {
                                    Button(L10n.text("Ответить", "Reply")) { replyingTo = comment }
                                        .font(.caption)
                                    if comment.user_id == authViewModel.userId() || video.user_id == authViewModel.userId() {
                                        Button(L10n.text("Удалить", "Delete"), role: .destructive) {
                                            Task {
                                                await VideoService.shared.deleteComment(commentId: comment.id, token: authViewModel.token())
                                                comments = await VideoService.shared.comments(videoId: video.id, token: authViewModel.token())
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !video.comments_locked {
                    HStack(spacing: 10) {
                        TextField(
                            replyingTo == nil ? L10n.text("Комментарий...", "Comment...") : L10n.text("Ответ...", "Reply..."),
                            text: $text
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Button(L10n.text("Отправить", "Send")) {
                            Task {
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                _ = await VideoService.shared.addComment(
                                    videoId: video.id,
                                    text: trimmed,
                                    parentCommentId: replyingTo?.id,
                                    token: authViewModel.token()
                                )
                                replyingTo = nil
                                text = ""
                                comments = await VideoService.shared.comments(videoId: video.id, token: authViewModel.token())
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral, useGradient: true))
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.7))
                }
            }
            .navigationTitle(L10n.text("Комментарии", "Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Закрыть", "Close")) { dismiss() }
                }
            }
            .task {
                comments = await VideoService.shared.comments(videoId: video.id, token: authViewModel.token())
            }
        }
    }
}

private struct AsyncAvatarView: View {
    let urlString: String?
    let fallback: String

    var body: some View {
        Group {
            if let urlString,
               let url = URL(string: urlString),
               url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.sky.opacity(0.7), AppTheme.coral.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(fallback.prefix(1)).uppercased())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}
