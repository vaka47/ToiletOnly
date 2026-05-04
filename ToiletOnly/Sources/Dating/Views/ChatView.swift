import SwiftUI

struct ChatView: View {
    let match: DatingMatch
    let onKeepDialog: () -> Void
    var onDeleteMatch: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var currentMatch: DatingMatch
    @State private var messages: [ChatMessageRow] = []
    @State private var inputText: String = ""
    @State private var socketTask: URLSessionWebSocketTask?
    @State private var isPingSent: Bool = false
    @State private var selectedProfile: DatingProfile?
    @State private var showActions: Bool = false
    @State private var showReportComposer: Bool = false
    @State private var reportReason: String = ""

    init(match: DatingMatch, onKeepDialog: @escaping () -> Void, onDeleteMatch: @escaping () -> Void = {}) {
        self.match = match
        self.onKeepDialog = onKeepDialog
        self.onDeleteMatch = onDeleteMatch
        _currentMatch = State(initialValue: match)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                messagesView
                footer
            }
        }
        .onAppear {
            Task {
                await refreshMatch()
                await loadHistory()
            }
            connect()
        }
        .onDisappear {
            socketTask?.cancel(with: .goingAway, reason: nil)
        }
        .sheet(item: $selectedProfile) { profile in
            ProfileInfoView(profile: profile)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showReportComposer) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("Опиши коротко, что произошло в диалоге.", "Describe briefly what happened in the chat."))
                        .font(.subheadline)
                        .foregroundColor(AppTheme.muted)
                    TextEditor(text: $reportReason)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                            Task {
                                await ReportService.shared.report(
                                    targetUserId: currentMatch.profile.remoteUserId,
                                    type: "chat",
                                    reason: reportReason.trimmingCharacters(in: .whitespacesAndNewlines),
                                    objectId: currentMatch.id.uuidString,
                                    token: authViewModel.token()
                                )
                                reportReason = ""
                                showReportComposer = false
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(L10n.text("Действия с диалогом", "Chat actions"), isPresented: $showActions, titleVisibility: .visible) {
            Button(L10n.text("Удалить чат и мэтч", "Delete chat and match"), role: .destructive) {
                Task { await deleteMatch() }
            }
            Button(L10n.text("Пожаловаться", "Report")) {
                showReportComposer = true
            }
            Button(L10n.text("Заблокировать", "Block"), role: .destructive) {
                Task { await blockUser() }
            }
            Button(L10n.text("Отмена", "Cancel"), role: .cancel) {}
        }
        .alert(L10n.text("Приглашение отправлено", "Invitation sent"), isPresented: $isPingSent) {
            Button(L10n.text("Ок", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.text("Человеку ушел пуш, что ты ждешь его в онлайне.", "The other user got a push that you are waiting online."))
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await openProfile() }
                } label: {
                    HStack(spacing: 12) {
                        ChatAvatar(urlString: currentMatch.profile.photos.first, fallback: currentMatch.profile.name)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentMatch.profile.hideAge ? currentMatch.profile.name : "\(currentMatch.profile.name), \(currentMatch.profile.age)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.ink)
                            Text(headerSubtitle)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if currentMatch.profile.isOnline {
                    SessionCountdownPill(expiresAt: currentMatch.profile.sessionExpiresAt, accent: AppTheme.mint)
                } else if currentMatch.status != .kept {
                    sessionCountPill
                }

                Button {
                    showActions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.84))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if currentMatch.status != .kept || !currentMatch.profile.isOnline {
                HStack(spacing: 8) {
                    if currentMatch.status != .kept {
                        matchStatusBanner
                    }
                    if !currentMatch.profile.isOnline {
                        Text(L10n.text("Сейчас офлайн", "Offline now"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.coral)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AppTheme.coral.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.84))
                .shadow(color: AppTheme.shadow, radius: 16, x: 0, y: 10)
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(messages) { message in
                        HStack {
                            if message.isMine { Spacer(minLength: 48) }

                            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                                Text(message.text)
                                    .font(.body)
                                    .foregroundColor(message.isMine ? .white : AppTheme.ink)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        Group {
                                            if message.isMine {
                                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                    .fill(AppTheme.accentGradient)
                                            } else {
                                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                    .fill(Color.white.opacity(0.88))
                                            }
                                        }
                                    )
                                Text(message.createdAtText)
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.muted)
                            }
                            .id(message.id)

                            if !message.isMine { Spacer(minLength: 48) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .onChange(of: messages.count) { _ in
                if let last = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if shouldShowActionDock {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if currentMatch.status != .kept {
                            if currentMatch.status == .awaitingOther {
                                Text(keepButtonTitle)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(AppTheme.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.white.opacity(0.84))
                                    )
                            } else {
                                Button {
                                    onKeepDialog()
                                    Task {
                                        try? await Task.sleep(nanoseconds: 350_000_000)
                                        await refreshMatch()
                                    }
                                } label: {
                                    Label(keepButtonTitle, systemImage: "bookmark.fill")
                                }
                                .buttonStyle(PrimaryButtonStyle(tint: AppTheme.mint))
                            }
                        }

                        if !currentMatch.profile.isOnline {
                            Button {
                                Task {
                                    await PingService.shared.send(
                                        targetUserId: currentMatch.profile.remoteUserId,
                                        message: L10n.text("Зайди в приложение, я в онлайне", "Open the app, I am online"),
                                        token: authViewModel.token()
                                    )
                                    isPingSent = true
                                }
                            } label: {
                                Label(L10n.text("Позвать в туалет", "Invite online"), systemImage: "bell.badge.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle(tint: AppTheme.sky))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(L10n.text("Написать сообщение...", "Write a message..."), text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                    )

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.accentGradient)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.68))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        )
    }

    private var headerSubtitle: String {
        if currentMatch.status == .kept {
            return L10n.text("Сохраненный диалог", "Saved chat")
        }
        if currentMatch.profile.isOnline {
            return L10n.text("Сейчас в онлайне", "Online right now")
        }
        return L10n.text("Эфемерный мэтч", "Ephemeral match")
    }

    private var keepButtonTitle: String {
        switch currentMatch.status {
        case .confirmKeep:
            return L10n.text("Сохранить чат", "Save chat")
        case .awaitingOther:
            return L10n.text("Ждем подтверждение", "Waiting for confirmation")
        default:
            return L10n.text("Сохранить чат", "Save chat")
        }
    }

    private var shouldShowActionDock: Bool {
        (currentMatch.status != .kept) || !currentMatch.profile.isOnline
    }

    private var sessionCountPill: some View {
        Text(
            L10n.text(
                "\(currentMatch.mySessionsLeft)/\(currentMatch.otherSessionsLeft) сессии",
                "\(currentMatch.mySessionsLeft)/\(currentMatch.otherSessionsLeft) sessions"
            )
        )
        .font(.caption.weight(.semibold))
        .foregroundColor(AppTheme.coral)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.coral.opacity(0.12))
        .clipShape(Capsule())
    }

    private var matchStatusBanner: some View {
        Text(matchStatusText)
            .font(.caption.weight(.semibold))
            .foregroundColor(AppTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.72))
            .clipShape(Capsule())
    }

    private var matchStatusText: String {
        switch currentMatch.status {
        case .confirmKeep:
            return L10n.text("Второй пользователь уже предложил сохранить чат", "The other user already proposed saving the chat")
        case .awaitingOther:
            return L10n.text("Ты уже предложил сохранить чат", "You already asked to save this chat")
        case .pendingKeep:
            return L10n.text("Чат сгорит, если оба его не сохранят", "The chat will burn unless both users save it")
        case .kept:
            return L10n.text("Диалог сохранен", "Chat is saved")
        case .expired:
            return L10n.text("Мэтч истек", "Match expired")
        }
    }

    private func connect() {
        socketTask = ChatWebSocketService.shared.connect(matchId: currentMatch.id.uuidString, token: authViewModel.token()) { text in
            DispatchQueue.main.async {
                messages.append(ChatMessageRow(id: UUID().uuidString, text: text, isMine: false, createdAtText: timeString(Date())))
            }
        }
    }

    private func loadHistory() async {
        guard let token = authViewModel.token() else { return }
        let items = await MessageService.shared.fetch(matchId: currentMatch.id.uuidString, token: token)
        let me = authViewModel.userId()
        messages = items.map { dto in
            ChatMessageRow(
                id: dto.id,
                text: dto.text,
                isMine: dto.sender_id == me,
                createdAtText: formatTimestamp(dto.created_at)
            )
        }
    }

    private func refreshMatch() async {
        guard let dto = await MatchService.shared.fetch(matchId: currentMatch.id.uuidString, token: authViewModel.token()) else { return }
        currentMatch = DatingMatch.fromBackend(dto, profile: currentMatch.profile, createdAt: currentMatch.createdAt)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(
            ChatMessageRow(
                id: UUID().uuidString,
                text: trimmed,
                isMine: true,
                createdAtText: timeString(Date())
            )
        )
        ChatWebSocketService.shared.send(task: socketTask, text: trimmed)
        Task { await MessageService.shared.post(matchId: currentMatch.id.uuidString, token: authViewModel.token(), text: trimmed) }
        inputText = ""
    }

    private func openProfile() async {
        guard let dto = await ProfileService.shared.fetchProfile(userId: currentMatch.profile.remoteUserId, token: authViewModel.token()) else {
            selectedProfile = currentMatch.profile
            return
        }
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
            distanceKm: currentMatch.profile.distanceKm,
            sessionExpiresAt: parseDate(dto.session_expires_at)
        )
    }

    private func deleteMatch() async {
        let ok = await MatchService.shared.delete(matchId: currentMatch.id.uuidString, token: authViewModel.token())
        guard ok else { return }
        onDeleteMatch()
        dismiss()
    }

    private func blockUser() async {
        await BlockService.shared.block(userId: currentMatch.profile.remoteUserId, token: authViewModel.token())
        _ = await MatchService.shared.delete(matchId: currentMatch.id.uuidString, token: authViewModel.token())
        onDeleteMatch()
        dismiss()
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private func formatTimestamp(_ raw: String) -> String {
        if let date = parseDate(raw) {
            return timeString(date)
        }
        return raw
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ChatMessageRow: Identifiable, Hashable {
    let id: String
    let text: String
    let isMine: Bool
    let createdAtText: String
}

private struct ChatAvatar: View {
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
        .frame(width: 54, height: 54)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.sky.opacity(0.72), AppTheme.coral.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(fallback.prefix(1)).uppercased())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}
