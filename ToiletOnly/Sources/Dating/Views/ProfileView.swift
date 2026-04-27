import SwiftUI
import AVKit

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showVideoSheet: Bool = false
    @State private var showSetupSheet: Bool = false
    @StateObject private var recorder = VideoRecorder()
    @State private var profile: ProfileOutDTO?
    @State private var myVideos: [VideoDTO] = []
    @State private var selectedTab: String = "bio"
    @State private var showDeleteAccountAlert: Bool = false
    @State private var showBlockedUsersSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                summaryCard
                actionRow

                Picker("tab", selection: $selectedTab) {
                    Text(L10n.text("Био", "Bio")).tag("bio")
                    Text(L10n.text("Видео", "Videos")).tag("videos")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if selectedTab == "bio" {
                    bioTab
                } else {
                    videosTab
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 22)
        }
        .sheet(isPresented: $showVideoSheet) {
            VideoRecorderView(recorder: recorder, token: authViewModel.token())
        }
        .sheet(isPresented: $showBlockedUsersSheet) {
            BlockedUsersView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showSetupSheet) {
            ProfileSetupView(existingProfile: profile) {
                showSetupSheet = false
                Task { await reloadAll() }
            }
        }
        .alert(L10n.text("Удалить профиль?", "Delete profile?"), isPresented: $showDeleteAccountAlert) {
            Button(L10n.text("Удалить", "Delete"), role: .destructive) {
                Task {
                    let ok = await ProfileService.shared.deleteMyProfile(token: authViewModel.token())
                    if ok { authViewModel.signOut() }
                }
            }
            Button(L10n.text("Отмена", "Cancel"), role: .cancel) {}
        }
        .task {
            await reloadAll()
            if profile == nil {
                showSetupSheet = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("Профиль", "Profile"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                Text(L10n.text("Фото, био и архив видео.", "Photos, bio, and video archive."))
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)
            }
            Spacer()
            Button {
                showBlockedUsersSheet = true
            } label: {
                Image(systemName: "hand.raised.slash.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.80))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Button {
                showSetupSheet = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.80))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Menu {
                Button(L10n.text("Редактировать", "Edit")) { showSetupSheet = true }
                Button(L10n.text("Блок-лист", "Blocked users")) { showBlockedUsersSheet = true }
                Button(L10n.text("Выйти", "Sign out"), role: .destructive) { authViewModel.signOut() }
                Button(L10n.text("Удалить профиль", "Delete profile"), role: .destructive) {
                    showDeleteAccountAlert = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.80))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(L10n.text("Записать видео", "Record video")) {
                showVideoSheet = true
            }
            .buttonStyle(PrimaryButtonStyle(tint: AppTheme.mint))

            Button(L10n.text("Редактировать", "Edit")) {
                showSetupSheet = true
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 16)
    }

    private var summaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                if let profile {
                    Text(profile.hide_age ? profile.display_name : "\(profile.display_name), \(profile.age)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    HStack(spacing: 8) {
                        AccentTag(title: localizedGender(profile.gender), tint: AppTheme.sky)
                        ForEach(profile.looking_for_genders, id: \.self) { item in
                            AccentTag(title: L10n.text("Ищу: \(localizedGender(item))", "Looking for: \(localizedGender(item))"), tint: AppTheme.mint)
                        }
                    }
                    if !profile.bio_text.isEmpty {
                        Text(profile.bio_text)
                            .foregroundColor(AppTheme.muted)
                    }
                } else {
                    Text(L10n.text("Профиль пока пустой.", "Profile is empty."))
                        .foregroundColor(AppTheme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var bioTab: some View {
        VStack(spacing: 16) {
            mediaSection(title: L10n.text("Toilet selfie", "Toilet selfie")) {
                if let profile, let url = URL(string: profile.toilet_selfie_url), url.scheme?.hasPrefix("http") == true {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.gray.opacity(0.2)
                        }
                    }
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 220)
                }
            }

            mediaSection(title: L10n.text("Фото", "Photos")) {
                if let profile, !profile.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(profile.photos, id: \.self) { url in
                                RemoteImageTile(urlString: url)
                            }
                        }
                    }
                } else {
                    Text(L10n.text("Добавь дополнительные фото в редактировании профиля.", "Add more photos from profile edit."))
                        .foregroundColor(AppTheme.muted)
                }
            }
        }
    }

    private var videosTab: some View {
        VStack(spacing: 14) {
            if myVideos.isEmpty {
                AppCard {
                    Text(L10n.text("Пока нет видео. Запиши первое.", "No videos yet. Record your first one."))
                        .foregroundColor(AppTheme.muted)
                }
            } else {
                ForEach(myVideos) { video in
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            if let url = URL(string: video.asset_url) {
                                VideoPlayer(player: AVPlayer(url: url))
                                    .frame(height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            if !video.caption.isEmpty {
                                Text(video.caption)
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.muted)
                                    .lineLimit(3)
                            }
                            HStack {
                                Text("💬 \(video.comments_count)")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.muted)
                                Text("❤️ \(video.reactions_count)")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.muted)
                                Spacer()
                                Button(L10n.text("Удалить", "Delete"), role: .destructive) {
                                    Task {
                                        await VideoService.shared.deleteVideo(videoId: video.id, token: authViewModel.token())
                                        await reloadAll()
                                    }
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func mediaSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 16)
            AppCard { content() }
                .padding(.horizontal, 16)
        }
    }

    private func reloadAll() async {
        guard let token = authViewModel.token(), let userId = authViewModel.userId() else { return }
        profile = await ProfileService.shared.fetchProfile(userId: userId, token: token)
        myVideos = await VideoService.shared.byUser(userId: userId, token: token)
    }

    private func localizedGender(_ raw: String) -> String {
        switch raw {
        case "male":
            return L10n.text("мужчины", "men")
        case "female":
            return L10n.text("женщины", "women")
        case "other":
            return L10n.text("другое", "other")
        default:
            return L10n.text("не указан", "unknown")
        }
    }
}

private struct RemoteImageTile: View {
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: 132, height: 164)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 132, height: 164)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
