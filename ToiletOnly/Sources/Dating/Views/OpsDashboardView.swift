import SwiftUI

struct OpsDashboardView: View {
    private enum Tab: String, CaseIterable {
        case metrics
        case moderation
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var selectedTab: Tab = .metrics
    @State private var summary: OpsSummaryDTO?
    @State private var reports: [ReportModerationDTO] = []
    @State private var selectedWindowDays: Int = 30
    @State private var statusFilter: String = "open"
    @State private var isLoading: Bool = false
    @State private var selectedReport: ReportModerationDTO?

    private let metricColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCard
                        tabPicker

                        if selectedTab == .metrics {
                            metricsContent
                        } else {
                            moderationContent
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .refreshable {
                    await reload()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.text("Закрыть", "Close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(AppTheme.ink)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(AppTheme.ink)
                        }
                    }
                }
            }
            .sheet(item: $selectedReport) { report in
                OpsReportReviewSheet(report: report) { status, note in
                    Task {
                        if let updated = await OpsService.shared.updateReport(
                            reportId: report.id,
                            status: status,
                            note: note,
                            token: authViewModel.token()
                        ) {
                            await MainActor.run {
                                replaceReport(updated)
                                selectedReport = nil
                                if statusFilter != "all" && statusFilter != updated.status {
                                    reports.removeAll { $0.id == updated.id }
                                }
                            }
                            await reloadSummaryOnly()
                        }
                    }
                }
            }
            .task {
                await reload()
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.ink,
                            AppTheme.sky.opacity(0.94),
                            AppTheme.mint.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 10)
                .offset(x: 120, y: -44)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("Demo HQ", "Demo HQ"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(
                            L10n.text(
                                "Investor-ready панель: живые продуктовые метрики, safety queue и текущая температура демо.",
                                "Investor-ready panel with live product metrics, the safety queue, and the current demo pulse."
                            )
                        )
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.82))
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        heroBadge(
                            value: "\(summary?.window_days ?? selectedWindowDays)",
                            title: L10n.text("дней окна", "days")
                        )
                        heroBadge(
                            value: "\(summary?.moderation.open_count ?? 0)",
                            title: L10n.text("открытых жалоб", "open reports")
                        )
                    }
                }

                HStack(spacing: 10) {
                    windowButton(7)
                    windowButton(30)
                    windowButton(90)
                }
            }
            .padding(22)
        }
        .frame(height: 224)
        .shadow(color: AppTheme.shadow.opacity(1), radius: 22, x: 0, y: 14)
        .padding(.horizontal, 16)
    }

    private var tabPicker: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases, id: \.rawValue) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedTab = item
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item == .metrics ? "chart.line.uptrend.xyaxis" : "hand.raised.fill")
                        Text(item == .metrics ? L10n.text("Метрики", "Metrics") : L10n.text("Модерация", "Moderation"))
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundColor(selectedTab == item ? .white : AppTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selectedTab == item ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.68)))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var metricsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let summary {
                investorPulseCard(summary: summary)

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    metricTile(title: L10n.text("Всего юзеров", "Total users"), value: "\(summary.total_users)", tint: AppTheme.sky)
                    metricTile(title: L10n.text("Профили заполнены", "Profiles completed"), value: "\(summary.profiles_completed)", tint: AppTheme.mint)
                    metricTile(title: L10n.text("Активировались", "Activated users"), value: "\(summary.activated_users)", tint: AppTheme.coral)
                    metricTile(title: L10n.text("Стартов сессии", "Session starts"), value: "\(summary.session_starts)", tint: AppTheme.mango)
                    metricTile(title: L10n.text("Лайки", "Likes sent"), value: "\(summary.likes_sent)", tint: AppTheme.coral)
                    metricTile(title: L10n.text("Суперлайки", "Superlikes sent"), value: "\(summary.superlikes_sent)", tint: AppTheme.mango)
                    metricTile(title: L10n.text("Мэтчи", "Matches created"), value: "\(summary.matches_created)", tint: AppTheme.sky)
                    metricTile(title: L10n.text("Видео", "Videos published"), value: "\(summary.videos_published)", tint: AppTheme.mint)
                }
                .padding(.horizontal, 16)

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("Воронка", "Funnel"))
                            .font(.headline)
                            .foregroundColor(AppTheme.ink)

                        funnelRow(
                            title: L10n.text("Профиль -> активная сессия", "Profile -> active session"),
                            left: "\(summary.profiles_completed)",
                            right: "\(summary.activated_users)",
                            percent: summary.activation_rate,
                            tint: AppTheme.mint
                        )
                        funnelRow(
                            title: L10n.text("Лайк -> мэтч", "Like -> match"),
                            left: "\(summary.likes_sent + summary.superlikes_sent)",
                            right: "\(summary.matches_created)",
                            percent: summary.like_to_match_rate,
                            tint: AppTheme.coral
                        )
                        funnelRow(
                            title: L10n.text("Мэтч -> первое сообщение", "Match -> first message"),
                            left: "\(summary.matches_created)",
                            right: "\(summary.matches_with_messages)",
                            percent: summary.match_to_first_message_rate,
                            tint: AppTheme.sky
                        )
                        funnelRow(
                            title: L10n.text("Сообщение -> сохраненный чат", "Message -> kept chat"),
                            left: "\(summary.matches_with_messages)",
                            right: "\(summary.kept_matches)",
                            percent: summary.message_to_kept_rate,
                            tint: AppTheme.mango
                        )
                    }
                }
                .padding(.horizontal, 16)

                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("Safety / moderation", "Safety / moderation"))
                            .font(.headline)
                            .foregroundColor(AppTheme.ink)
                        HStack(spacing: 10) {
                            statusChip(L10n.text("Открыто \(summary.moderation.open_count)", "Open \(summary.moderation.open_count)"), tint: AppTheme.coral)
                            statusChip(L10n.text("В review \(summary.moderation.reviewing_count)", "Review \(summary.moderation.reviewing_count)"), tint: AppTheme.sky)
                            statusChip(L10n.text("Решено \(summary.moderation.resolved_count)", "Resolved \(summary.moderation.resolved_count)"), tint: AppTheme.mint)
                            statusChip(L10n.text("Отклонено \(summary.moderation.dismissed_count)", "Dismissed \(summary.moderation.dismissed_count)"), tint: AppTheme.mango)
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                placeholderCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: L10n.text("Метрики загружаются", "Metrics are loading"),
                    subtitle: L10n.text("Как только backend ответит, здесь появится investor view по воронке.", "As soon as the backend responds, the investor funnel view will appear here.")
                )
            }
        }
    }

    private var moderationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("Очередь жалоб", "Report queue"))
                        .font(.headline)
                        .foregroundColor(AppTheme.ink)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            reportFilterButton("all", title: L10n.text("Все", "All"))
                            reportFilterButton("open", title: L10n.text("Открытые", "Open"))
                            reportFilterButton("reviewing", title: L10n.text("В работе", "In review"))
                            reportFilterButton("resolved", title: L10n.text("Решенные", "Resolved"))
                            reportFilterButton("dismissed", title: L10n.text("Отклоненные", "Dismissed"))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            if reports.isEmpty {
                placeholderCard(
                    icon: "checkmark.shield",
                    title: L10n.text("Очередь чистая", "Queue is clear"),
                    subtitle: L10n.text("Здесь появятся profile/chat/video reports для показа moderation workflow.", "Profile, chat, and video reports will appear here to demonstrate the moderation workflow.")
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(reports) { report in
                        Button {
                            selectedReport = report
                        } label: {
                            AppCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("\(localizedReportType(report.report_type)) · \(report.target_display_name)")
                                                .font(.headline)
                                                .foregroundColor(AppTheme.ink)
                                            Text(
                                                L10n.text(
                                                    "Репортер: \(report.reporter_display_name)",
                                                    "Reporter: \(report.reporter_display_name)"
                                                )
                                            )
                                            .font(.subheadline)
                                            .foregroundColor(AppTheme.muted)
                                        }
                                        Spacer()
                                        statusChip(localizedStatus(report.status), tint: statusColor(report.status))
                                    }

                                    if let reason = report.reason, !reason.isEmpty {
                                        Text(reason)
                                            .font(.callout)
                                            .foregroundColor(AppTheme.ink)
                                            .multilineTextAlignment(.leading)
                                    }

                                    HStack(spacing: 10) {
                                        if let objectId = report.object_id, !objectId.isEmpty {
                                            tinyMeta(title: "ID", value: objectId)
                                        }
                                        tinyMeta(title: L10n.text("Создано", "Created"), value: relativeTime(report.created_at))
                                    }

                                    if let note = report.reviewed_note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundColor(AppTheme.muted)
                                            .padding(.top, 2)
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

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        async let summaryTask = OpsService.shared.summary(windowDays: selectedWindowDays, token: authViewModel.token())
        async let reportsTask = OpsService.shared.reports(status: statusFilter, token: authViewModel.token())
        summary = await summaryTask
        reports = await reportsTask
    }

    @MainActor
    private func reloadSummaryOnly() async {
        summary = await OpsService.shared.summary(windowDays: selectedWindowDays, token: authViewModel.token())
    }

    private func windowButton(_ days: Int) -> some View {
        Button {
            selectedWindowDays = days
            Task { await reload() }
        } label: {
            Text(L10n.text("\(days) дн", "\(days)d"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(selectedWindowDays == days ? AppTheme.ink : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(selectedWindowDays == days ? Color.white : Color.white.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func heroBadge(value: String, title: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func investorPulseCard(summary: OpsSummaryDTO) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("Investor pulse", "Investor pulse"))
                            .font(.headline)
                            .foregroundColor(AppTheme.ink)
                        Text(
                            L10n.text(
                                "Сверху видно, есть ли у продукта живой loop: заходят, лайкают, мэтчатся, пишут и сохраняют диалог.",
                                "This is where you can see if the product has a live loop: users join, like, match, message, and keep the chat."
                            )
                        )
                        .font(.subheadline)
                        .foregroundColor(AppTheme.muted)
                    }
                    Spacer()
                    AccentTag(
                        title: percentText(summary.video_publish_rate),
                        tint: AppTheme.mint
                    )
                }

                HStack(spacing: 10) {
                    highlightPill(
                        title: L10n.text("Completion", "Completion"),
                        value: percentText(summary.profile_completion_rate),
                        tint: AppTheme.sky
                    )
                    highlightPill(
                        title: L10n.text("Activation", "Activation"),
                        value: percentText(summary.activation_rate),
                        tint: AppTheme.mint
                    )
                    highlightPill(
                        title: L10n.text("Like -> Match", "Like -> Match"),
                        value: percentText(summary.like_to_match_rate),
                        tint: AppTheme.coral
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func metricTile(title: String, value: String, tint: Color) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(tint)
                            .frame(width: 46)
                    }
            }
        }
    }

    private func funnelRow(title: String, left: String, right: String, percent: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Text("\(left) → \(right)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.muted)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(18, proxy.size.width * CGFloat(min(max(percent / 100, 0), 1))))
                }
            }
            .frame(height: 10)
            Text(percentText(percent))
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
        }
    }

    private func reportFilterButton(_ status: String, title: String) -> some View {
        Button {
            statusFilter = status
            Task { await reload() }
        } label: {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(statusFilter == status ? .white : AppTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(statusFilter == status ? AnyShapeStyle(AppTheme.actionGradient) : AnyShapeStyle(Color.white.opacity(0.74)))
                )
        }
        .buttonStyle(.plain)
    }

    private func highlightPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppTheme.muted)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func tinyMeta(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundColor(AppTheme.muted)
            Text(value)
                .foregroundColor(AppTheme.ink)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.66))
        .clipShape(Capsule())
    }

    private func placeholderCard(icon: String, title: String, subtitle: String) -> some View {
        AppCard {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
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
            .padding(.vertical, 24)
        }
        .padding(.horizontal, 16)
    }

    @MainActor
    private func replaceReport(_ updated: ReportModerationDTO) {
        if let index = reports.firstIndex(where: { $0.id == updated.id }) {
            reports[index] = updated
        } else {
            reports.insert(updated, at: 0)
        }
    }

    private func localizedStatus(_ raw: String) -> String {
        switch raw {
        case "reviewing":
            return L10n.text("В работе", "In review")
        case "resolved":
            return L10n.text("Решено", "Resolved")
        case "dismissed":
            return L10n.text("Отклонено", "Dismissed")
        default:
            return L10n.text("Открыта", "Open")
        }
    }

    private func localizedReportType(_ raw: String) -> String {
        switch raw {
        case "chat":
            return L10n.text("Жалоба на чат", "Chat report")
        case "video":
            return L10n.text("Жалоба на видео", "Video report")
        case "photo":
            return L10n.text("Жалоба на фото", "Photo report")
        default:
            return L10n.text("Жалоба на профиль", "Profile report")
        }
    }

    private func statusColor(_ raw: String) -> Color {
        switch raw {
        case "reviewing":
            return AppTheme.sky
        case "resolved":
            return AppTheme.mint
        case "dismissed":
            return AppTheme.mango
        default:
            return AppTheme.coral
        }
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func relativeTime(_ raw: String?) -> String {
        guard let raw, let date = parseDate(raw) else { return raw ?? "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

private struct OpsReportReviewSheet: View {
    let report: ReportModerationDTO
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var status: String
    @State private var note: String

    init(report: ReportModerationDTO, onSave: @escaping (String, String) -> Void) {
        self.report = report
        self.onSave = onSave
        _status = State(initialValue: report.status)
        _note = State(initialValue: report.reviewed_note ?? report.reason ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(report.target_display_name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)

                Text(L10n.text("Репортер: \(report.reporter_display_name)", "Reporter: \(report.reporter_display_name)"))
                    .font(.subheadline)
                    .foregroundColor(AppTheme.muted)

                Picker("status", selection: $status) {
                    Text(L10n.text("Открыта", "Open")).tag("open")
                    Text(L10n.text("В работе", "Review")).tag("reviewing")
                    Text(L10n.text("Решена", "Resolved")).tag("resolved")
                    Text(L10n.text("Отклонена", "Dismissed")).tag("dismissed")
                }
                .pickerStyle(.segmented)

                if let reason = report.reason, !reason.isEmpty {
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("Причина", "Reason"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppTheme.muted)
                            Text(reason)
                                .font(.body)
                                .foregroundColor(AppTheme.ink)
                        }
                    }
                }

                TextEditor(text: $note)
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
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle(L10n.text("Review report", "Review report"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.text("Отмена", "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Сохранить", "Save")) {
                        onSave(status, note)
                    }
                }
            }
        }
    }
}
