import SwiftUI

struct BlockedUsersView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [BlockedUserRow] = []
    @State private var isLoading: Bool = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading && items.isEmpty {
                        AppCard {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                        .padding(.horizontal, 16)
                    } else if items.isEmpty {
                        AppCard {
                            VStack(spacing: 10) {
                                Image(systemName: "hand.raised.slash")
                                    .font(.system(size: 28))
                                    .foregroundColor(AppTheme.sky)
                                Text(L10n.text("Блок-лист пуст", "Block list is empty"))
                                    .font(.headline)
                                    .foregroundColor(AppTheme.ink)
                                Text(L10n.text("Здесь будут пользователи, которых ты скрыл из ленты и диалогов.", "Users you hide from the feed and chats will appear here."))
                                    .font(.callout)
                                    .foregroundColor(AppTheme.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                        }
                        .padding(.horizontal, 16)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(items) { item in
                                AppCard {
                                    HStack(spacing: 12) {
                                        if let avatar = item.avatarURL {
                                            AsyncImage(url: avatar) { phase in
                                                if let image = phase.image {
                                                    image.resizable().scaledToFill()
                                                } else {
                                                    Color.gray.opacity(0.16)
                                                }
                                            }
                                            .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.16))
                                                .frame(width: 60, height: 60)
                                        }

                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.name)
                                                .font(.headline)
                                                .foregroundColor(AppTheme.ink)
                                            Text("\(item.age), \(localizedGender(item.gender))")
                                                .font(.caption)
                                                .foregroundColor(AppTheme.muted)
                                            if !item.bio.isEmpty {
                                                Text(item.bio)
                                                    .font(.callout)
                                                    .foregroundColor(AppTheme.muted)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()

                                        Button(L10n.text("Разблокировать", "Unblock")) {
                                            Task { await unblock(item) }
                                        }
                                        .buttonStyle(PrimaryButtonStyle(tint: AppTheme.sky))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 22)
                    }
                }
                .padding(.top, 10)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Закрыть", "Close")) {
                        dismiss()
                    }
                }
            }
            .task {
                await reload()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Блок-лист", "Blocked users"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                Text(L10n.text("Управление скрытыми пользователями.", "Manage hidden users."))
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)
            }
            Spacer()
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.82))
                    .foregroundColor(AppTheme.ink)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func reload() async {
        guard let token = authViewModel.token() else { return }
        isLoading = true
        let blocks = await BlockService.shared.list(token: token)
        var rows: [BlockedUserRow] = []
        for block in blocks {
            if let profile = await ProfileService.shared.fetchProfile(userId: block.blocked_user_id, token: token) {
                rows.append(
                    BlockedUserRow(
                        userId: block.blocked_user_id,
                        name: profile.display_name,
                        age: profile.age,
                        gender: profile.gender,
                        bio: profile.bio_text.isEmpty ? profile.bio_ai : profile.bio_text,
                        avatarURL: URL(string: profile.toilet_selfie_url)
                    )
                )
            } else {
                rows.append(
                    BlockedUserRow(
                        userId: block.blocked_user_id,
                        name: L10n.text("Пользователь", "User"),
                        age: 18,
                        gender: "unknown",
                        bio: "",
                        avatarURL: nil
                    )
                )
            }
        }
        items = rows
        isLoading = false
    }

    private func unblock(_ item: BlockedUserRow) async {
        await BlockService.shared.unblock(userId: item.userId, token: authViewModel.token())
        items.removeAll { $0.userId == item.userId }
    }

    private func localizedGender(_ raw: String) -> String {
        switch raw {
        case "male":
            return L10n.text("мужчина", "man")
        case "female":
            return L10n.text("женщина", "woman")
        case "other":
            return L10n.text("другое", "other")
        default:
            return L10n.text("не указан", "unknown")
        }
    }
}

private struct BlockedUserRow: Identifiable {
    var id: String { userId }
    let userId: String
    let name: String
    let age: Int
    let gender: String
    let bio: String
    let avatarURL: URL?
}
