import SwiftUI

struct LiveDatingView: View {
    @ObservedObject var viewModel: DatingViewModel
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showVideoSheet: Bool = false
    @State private var showInfoSheet: Bool = false
    @State private var selectedMatch: DatingMatch?
    @State private var showSuperlikeSheet: Bool = false
    @State private var superlikeMessage: String = ""
    @State private var moderationTarget: DatingProfile?
    @State private var showModerationDialog: Bool = false
    @State private var showReportSheet: Bool = false
    @State private var reportReason: String = ""
    @StateObject private var recorder = VideoRecorder()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                heroHeader

                if let profile = viewModel.currentProfile {
                    ProfileCardView(
                        profile: profile,
                        remainingSuperLikes: viewModel.remainingSuperLikesToday,
                        onSkip: {
                            Task { await viewModel.passCurrent(token: authViewModel.token()) }
                        },
                        onLike: {
                            Task {
                                if let newMatch = await viewModel.likeCurrent(token: authViewModel.token()) {
                                    selectedMatch = newMatch
                                }
                            }
                        },
                        onSuperLike: {
                            superlikeMessage = ""
                            showSuperlikeSheet = true
                        },
                        onMore: {
                            moderationTarget = profile
                            showModerationDialog = true
                        }
                    )
                    .environmentObject(authViewModel)
                    .padding(.horizontal, 12)

                    if !viewModel.activeMatches.isEmpty {
                        quickMatchStrip
                    }
                } else {
                    emptyState
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .sheet(isPresented: $showVideoSheet) {
            VideoRecorderView(recorder: recorder, token: authViewModel.token())
        }
        .sheet(item: $selectedMatch) { match in
            ChatView(match: match) {
                Task {
                    await viewModel.keepMatch(match, token: authViewModel.token())
                    if let refreshed = viewModel.activeMatches.first(where: { $0.id == match.id }) {
                        selectedMatch = refreshed
                    }
                }
            }
            .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showSuperlikeSheet) {
            superlikeComposer
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showReportSheet) {
            reportComposer
                .presentationDetents([.medium])
        }
        .task {
            await viewModel.loadFeed(token: authViewModel.token())
        }
        .onChange(of: viewModel.ageFilter) { _ in
            Task { await viewModel.loadFeed(token: authViewModel.token()) }
        }
        .alert(L10n.text("Суперлайк недоступен", "Superlike unavailable"), isPresented: Binding(
            get: { viewModel.superLikeError != nil },
            set: { if !$0 { viewModel.superLikeError = nil } }
        )) {
            Button(L10n.text("Ок", "OK"), role: .cancel) { viewModel.superLikeError = nil }
        } message: {
            Text(viewModel.superLikeError ?? "")
        }
        .confirmationDialog(
            L10n.text("Действия с профилем", "Profile actions"),
            isPresented: $showModerationDialog,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Пожаловаться", "Report")) {
                reportReason = ""
                showReportSheet = true
            }
            Button(L10n.text("Заблокировать", "Block"), role: .destructive) {
                guard let profile = moderationTarget else { return }
                Task {
                    await BlockService.shared.block(userId: profile.remoteUserId, token: authViewModel.token())
                    viewModel.block(profile: profile)
                }
            }
            Button(L10n.text("Отмена", "Cancel"), role: .cancel) {}
        }
    }

    private var heroHeader: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Анкеты рядом", "Profiles nearby"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.ink)
                        Text(L10n.text("Свайпни влево, чтобы пропустить. Вправо, чтобы лайкнуть. Вверх, чтобы раскрыть профиль.", "Swipe left to skip, right to like, up to expand profile."))
                            .font(.callout)
                            .foregroundColor(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        heroMetric(value: "\(viewModel.filteredProfiles.count)", title: L10n.text("в ленте", "in feed"), tint: AppTheme.sky)
                        heroMetric(value: "\(viewModel.remainingSuperLikesToday)", title: L10n.text("суперлайков", "superlikes"), tint: AppTheme.mango)
                    }
                }

                HStack(spacing: 10) {
                    heroChip(L10n.text("Свайп до мэтча", "Swipe to match"), tint: AppTheme.coral)
                    heroChip(L10n.text("Сначала онлайн", "Live now first"), tint: AppTheme.mint)
                    heroChip(L10n.text("Только в сессии", "Session-only"), tint: AppTheme.sky)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var quickMatchStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Активные диалоги", "Active chats"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Text(L10n.text("Последние мэтчи сверху", "Latest matches first"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.activeMatches.prefix(10)) { match in
                        Button {
                            selectedMatch = match
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(match.profile.name)
                                    .font(.headline)
                                    .foregroundColor(AppTheme.ink)
                                Text(matchLine(for: match))
                                    .font(.caption)
                                    .foregroundColor(AppTheme.muted)
                            }
                            .padding(14)
                            .frame(width: 182, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white.opacity(0.68))
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .shadow(color: AppTheme.shadow.opacity(0.9), radius: 14, x: 0, y: 10)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        AppCard {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundColor(AppTheme.coral)
                Text(L10n.text("Сейчас рядом никого нет", "No one nearby right now"))
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                Text(L10n.text("Открой следующую сессию позже или расширь радиус в фильтрах.", "Open the next session later or widen your search radius in filters."))
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
    }

    private var superlikeComposer: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("Суперлайк выделяется и может сразу открыть диалог. Можно приложить сообщение и оно попадет в чат при мэтче.", "A superlike stands out and can open the chat immediately. You can attach a message and it will appear in the chat after a match."))
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)

                HStack {
                    Text(L10n.text("Доступно сегодня", "Available today"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.remainingSuperLikesToday) / 5")
                        .font(.headline)
                        .foregroundColor(AppTheme.mango)
                }
                .padding(14)
                .background(Color.white.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                TextEditor(text: $superlikeMessage)
                    .frame(minHeight: 150)
                    .padding(12)
                    .background(Color.white.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(L10n.text("Отправить суперлайк", "Send superlike")) {
                    Task {
                        if let newMatch = await viewModel.superLikeCurrent(
                            token: authViewModel.token(),
                            message: superlikeMessage
                        ) {
                            selectedMatch = newMatch
                        }
                        showSuperlikeSheet = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: AppTheme.mango))

                Spacer()
            }
            .padding(20)
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle(L10n.text("Суперлайк", "Superlike"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Закрыть", "Close")) {
                        showSuperlikeSheet = false
                    }
                }
            }
        }
    }

    private var reportComposer: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("Опиши коротко, что произошло. Жалоба уйдет в moderation queue.", "Describe briefly what happened. The report will be sent to the moderation queue."))
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)

                TextEditor(text: $reportReason)
                    .frame(minHeight: 160)
                    .padding(12)
                    .background(Color.white.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(L10n.text("Отправить жалобу", "Send report")) {
                    Task {
                        if let profile = moderationTarget {
                            await ReportService.shared.report(
                                targetUserId: profile.remoteUserId,
                                type: "profile",
                                reason: reportReason,
                                token: authViewModel.token()
                            )
                        }
                        showReportSheet = false
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral, useGradient: true))

                Spacer()
            }
            .padding(20)
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle(L10n.text("Пожаловаться", "Report"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Закрыть", "Close")) {
                        showReportSheet = false
                    }
                }
            }
        }
    }

    private func matchLine(for match: DatingMatch) -> String {
        switch match.status {
        case .pendingKeep:
            return L10n.text("Осталось \(match.mySessionsLeft) входа", "\(match.mySessionsLeft) entries left")
        case .confirmKeep:
            return L10n.text("Нужно подтвердить", "Need confirmation")
        case .awaitingOther:
            return L10n.text("Ждет второго", "Waiting for the other user")
        case .kept:
            return L10n.text("Сохранен", "Saved")
        case .expired:
            return L10n.text("Сгорел", "Expired")
        }
    }

    private func heroChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func heroMetric(value: String, title: String, tint: Color) -> some View {
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
