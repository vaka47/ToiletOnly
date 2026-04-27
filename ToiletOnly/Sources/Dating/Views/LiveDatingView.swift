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
                if let profile = viewModel.currentProfile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Анкеты рядом", "Profiles nearby"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.ink)
                        Text(L10n.text("Свайпни влево, чтобы пропустить. Вправо, чтобы лайкнуть. Вверх, чтобы раскрыть профиль.", "Swipe left to skip, right to like, up to expand profile."))
                            .font(.callout)
                            .foregroundColor(AppTheme.muted)
                    }
                    .padding(.horizontal, 16)

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

    private var quickMatchStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Активные диалоги", "Active chats"))
                .font(.system(.headline, design: .rounded))
                .foregroundColor(AppTheme.ink)
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
                                    .fill(Color.white.opacity(0.72))
                                    .shadow(color: AppTheme.shadow, radius: 12, x: 0, y: 8)
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
}
