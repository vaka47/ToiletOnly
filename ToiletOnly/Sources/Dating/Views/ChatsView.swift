import SwiftUI

struct ChatsView: View {
    enum Tab: String {
        case matches
        case likedYou
    }

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var tab: Tab = .matches
    @State private var matches: [MatchListItemDTO] = []
    @State private var incomingLikes: [IncomingLikeDTO] = []
    @State private var selectedMatch: DatingMatch?
    @State private var selectedLike: IncomingLikeDTO?
    @State private var unreadMatchesCount: Int = 0
    @State private var unreadLikesCount: Int = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if tab == .matches {
                    matchesContent
                } else {
                    likesContent
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .sheet(item: $selectedMatch, onDismiss: {
            Task {
                await reload()
                await refreshUnreadSummary()
            }
        }) { match in
            ChatView(match: match) {
                Task {
                    _ = await MatchService.shared.keep(matchId: match.id.uuidString, token: authViewModel.token())
                    await reload()
                    if let refreshed = matches.first(where: { $0.id == match.id.uuidString }) {
                        selectedMatch = mapMatch(refreshed)
                    }
                }
            } onDeleteMatch: {
                Task {
                    selectedMatch = nil
                    await reload()
                }
            }
            .environmentObject(authViewModel)
        }
        .sheet(item: $selectedLike) { like in
            IncomingLikeSheet(
                item: like,
                onSkip: {
                    Task {
                        _ = await LikeService.shared.send(to: like.from_user_id, action: "pass", token: authViewModel.token())
                        incomingLikes.removeAll { $0.id == like.id }
                        selectedLike = nil
                        await refreshUnreadSummary()
                    }
                },
                onLike: {
                    Task {
                        let match = await LikeService.shared.send(to: like.from_user_id, action: "like", token: authViewModel.token())
                        incomingLikes.removeAll { $0.id == like.id }
                        selectedLike = nil
                        if let match {
                            selectedMatch = DatingMatch.fromBackend(match, profile: mapProfile(like), createdAt: Date())
                        }
                        await refreshUnreadSummary()
                    }
                }
            )
            .environmentObject(authViewModel)
        }
        .task {
            await reload()
            await markCurrentTabRead()
            await refreshUnreadSummary()
        }
        .onChange(of: tab) { _ in
            Task {
                await markCurrentTabRead()
                await refreshUnreadSummary()
            }
        }
    }

    private var header: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("Диалоги", "Chats"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.ink)
                        Text(L10n.text("Мэтчи, входящие лайки и чаты с таймером в одном месте.", "Matches, incoming likes, and expiring chats in one place."))
                            .font(.callout)
                            .foregroundColor(AppTheme.muted)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        headerMetric(value: "\(matches.count)", title: L10n.text("чатов", "chats"), tint: AppTheme.sky)
                        headerMetric(value: "\(incomingLikes.count)", title: L10n.text("лайков", "likes"), tint: AppTheme.coral)
                    }
                }

                HStack(spacing: 10) {
                    tabButton(.matches, icon: "bubble.left.and.bubble.right.fill", title: L10n.text("Мэтчи", "Matches"), count: unreadMatchesCount)
                    tabButton(.likedYou, icon: "heart.fill", title: L10n.text("Вас лайкнули", "Liked you"), count: unreadLikesCount)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var matchesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("Активные мэтчи", "Active matches"))
                        .font(.headline)
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(matches.prefix(20)) { match in
                                Button {
                                    selectedMatch = mapMatch(match)
                                } label: {
                                    VStack(spacing: 8) {
                                        AsyncAvatar(urlString: match.toilet_selfie_url, size: 72)
                                        Text(match.display_name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(AppTheme.ink)
                                            .lineLimit(1)
                                        Text(shortStatus(match))
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.muted)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 88)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("Диалоги", "Dialogs"))
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                    .padding(.horizontal, 16)

                if matches.isEmpty {
                    emptyCard(
                        icon: "bubble.left.and.bubble.right",
                        title: L10n.text("Пока нет диалогов", "No dialogs yet"),
                        subtitle: L10n.text("Когда появится мэтч, чат появится здесь.", "Once you get a match, chats will appear here.")
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(matches) { match in
                            Button {
                                selectedMatch = mapMatch(match)
                            } label: {
                                AppCard {
                                    HStack(spacing: 12) {
                                        AsyncAvatar(urlString: match.toilet_selfie_url, size: 60)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(match.display_name)
                                                .font(.headline)
                                                .foregroundColor(AppTheme.ink)
                                            Text(match.last_message ?? shortStatus(match))
                                                .font(.callout)
                                                .foregroundColor(AppTheme.muted)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 8) {
                                            if match.status != "kept" {
                                                SessionCountdownPill(expiresAt: parseDate(match.session_expires_at), accent: AppTheme.coral)
                                                Text(
                                                    L10n.text(
                                                        "\(match.my_sessions_left)/\(match.other_sessions_left) сессии",
                                                        "\(match.my_sessions_left)/\(match.other_sessions_left) sessions"
                                                    )
                                                )
                                                .font(.caption2)
                                                .foregroundColor(AppTheme.muted)
                                            } else {
                                                AccentTag(title: L10n.text("Сохранен", "Saved"), tint: AppTheme.mint)
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var likesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Запросы на мэтч", "Match requests"))
                .font(.headline)
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 16)

            if incomingLikes.isEmpty {
                emptyCard(
                    icon: "heart.slash",
                    title: L10n.text("Новых лайков пока нет", "No new likes yet"),
                    subtitle: L10n.text("Когда тебя лайкнут, профили появятся здесь.", "When someone likes you, their profiles will appear here.")
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 18)], spacing: 18) {
                    ForEach(incomingLikes) { item in
                        Button {
                            selectedLike = item
                        } label: {
                            VStack(spacing: 10) {
                                ZStack(alignment: .topTrailing) {
                                    AsyncAvatar(urlString: item.toilet_selfie_url, size: 82)
                                    if item.like_type == "superlike" {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(AppTheme.mango)
                                            .clipShape(Circle())
                                    }
                                }
                                Text(item.hide_age ? item.display_name : "\(item.display_name), \(item.age)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppTheme.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func tabButton(_ item: Tab, icon: String, title: String, count: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                tab = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundColor(tab == item ? AppTheme.ink : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tab == item ? Color.white : AppTheme.coral)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tab == item ? Color.white.opacity(0.80) : Color.white.opacity(0.58))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: AppTheme.shadow.opacity(0.9), radius: 14, x: 0, y: 10)
            )
            .foregroundColor(AppTheme.ink)
        }
        .buttonStyle(.plain)
    }

    private func emptyCard(icon: String, title: String, subtitle: String) -> some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(AppTheme.sky)
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .padding(.horizontal, 16)
    }

    private func reload() async {
        async let matchTask = MatchService.shared.list(token: authViewModel.token())
        async let likeTask = LikeService.shared.incoming(token: authViewModel.token())
        matches = await matchTask
        incomingLikes = await likeTask
    }

    private func refreshUnreadSummary() async {
        let summary = await ActivityService.shared.summary(token: authViewModel.token())
        unreadMatchesCount = summary.unread_matches_count
        unreadLikesCount = summary.unread_likes_count
    }

    private func markCurrentTabRead() async {
        let scope = tab == .matches ? "matches" : "likes"
        await ActivityService.shared.markRead(scope: scope, token: authViewModel.token())
    }

    private func shortStatus(_ item: MatchListItemDTO) -> String {
        if item.status == "kept" {
            return L10n.text("Сохранен", "Saved")
        }
        if item.other_is_kept && !item.my_is_kept {
            return L10n.text("Тебе предложили сохранить", "Keep request received")
        }
        if item.my_is_kept && !item.other_is_kept {
            return L10n.text("Ждешь подтверждение", "Waiting for confirmation")
        }
        return L10n.text("\(item.my_sessions_left) входа осталось", "\(item.my_sessions_left) entries left")
    }

    private func mapMatch(_ dto: MatchListItemDTO) -> DatingMatch {
        DatingMatch.fromBackend(
            MatchOutDTO(
                id: dto.id,
                user_a_id: "",
                user_b_id: "",
                status: dto.status,
                my_is_kept: dto.my_is_kept,
                other_is_kept: dto.other_is_kept,
                my_sessions_left: dto.my_sessions_left,
                other_sessions_left: dto.other_sessions_left
            ),
            profile: DatingProfile(
                id: UUID(uuidString: dto.other_user_id) ?? UUID(),
                remoteUserId: dto.other_user_id,
                name: dto.display_name,
                age: dto.age,
                hideAge: dto.hide_age,
                gender: dto.gender,
                bio: "",
                photos: [dto.toilet_selfie_url],
                sessionVideoURL: nil,
                toiletSelfieIndex: 0,
                tags: [],
                isOnline: dto.is_online_toilet,
                distanceKm: nil,
                sessionExpiresAt: parseDate(dto.session_expires_at)
            ),
            createdAt: parseDate(dto.last_message_at) ?? Date()
        )
    }

    private func mapProfile(_ dto: IncomingLikeDTO) -> DatingProfile {
        DatingProfile(
            id: UUID(uuidString: dto.from_user_id) ?? UUID(),
            remoteUserId: dto.from_user_id,
            name: dto.display_name,
            age: dto.age,
            hideAge: dto.hide_age,
            gender: dto.gender,
            bio: dto.bio_text.isEmpty ? dto.bio_ai : dto.bio_text,
            photos: [dto.toilet_selfie_url] + dto.photos,
            sessionVideoURL: dto.session_video_url,
            toiletSelfieIndex: 0,
            tags: dto.interests,
            isOnline: dto.is_online_toilet,
            distanceKm: nil,
            sessionExpiresAt: parseDate(dto.session_expires_at)
        )
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func headerMetric(value: String, title: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppTheme.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct IncomingLikeSheet: View {
    let item: IncomingLikeDTO
    let onSkip: () -> Void
    let onLike: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ProfileInfoView(profile: DatingProfile(
                    id: UUID(uuidString: item.from_user_id) ?? UUID(),
                    remoteUserId: item.from_user_id,
                    name: item.display_name,
                    age: item.age,
                    hideAge: item.hide_age,
                    gender: item.gender,
                    bio: item.bio_text.isEmpty ? item.bio_ai : item.bio_text,
                    photos: [item.toilet_selfie_url] + item.photos,
                    sessionVideoURL: item.session_video_url,
                    toiletSelfieIndex: 0,
                    tags: item.interests,
                    isOnline: item.is_online_toilet,
                    distanceKm: nil,
                    sessionExpiresAt: nil
                ))
                .environmentObject(authViewModel)

                HStack(spacing: 12) {
                    Button(L10n.text("Скип", "Skip"), action: onSkip)
                        .buttonStyle(GhostButtonStyle())
                    Button(L10n.text("Лайкнуть", "Like"), action: onLike)
                        .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral, useGradient: true))
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .background(AppBackground().ignoresSafeArea())
        }
    }
}

private struct AsyncAvatar: View {
    let urlString: String
    let size: CGFloat

    var body: some View {
        if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.18)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.18))
                .frame(width: size, height: size)
        }
    }
}
