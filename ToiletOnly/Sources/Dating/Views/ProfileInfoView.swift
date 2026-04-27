import SwiftUI
import AVKit

struct ProfileInfoView: View {
    let profile: DatingProfile
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var tab: String = "bio"
    @State private var videos: [VideoDTO] = []
    @State private var selectedVideo: VideoDTO?

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Picker("Tab", selection: $tab) {
                    Text(L10n.text("Био", "Bio")).tag("bio")
                    Text(L10n.text("Видео", "Videos")).tag("videos")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if tab == "bio" {
                    bioTab
                } else {
                    videosTab
                }
            }
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                videos = await VideoService.shared.byUser(userId: profile.remoteUserId, token: authViewModel.token())
            }
            .sheet(item: $selectedVideo) { video in
                VideoCommentsSheet(video: video)
                    .environmentObject(authViewModel)
            }
        }
    }

    private var bioTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(profile.hideAge ? profile.name : "\(profile.name), \(profile.age)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Text(profile.bio)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                if !profile.tags.isEmpty {
                    AppCard {
                        HStack {
                            ForEach(profile.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.cream)
                                    .cornerRadius(999)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var videosTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(videos) { video in
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            if let url = URL(string: video.asset_url) {
                                VideoPlayer(player: AVPlayer(url: url))
                                    .frame(height: 220)
                                    .cornerRadius(12)
                            }
                            if !video.caption.isEmpty {
                                Text(video.caption)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            HStack {
                                Text("💬 \(video.comments_count)")
                                    .font(.caption)
                                Text("❤️ \(video.reactions_count)")
                                    .font(.caption)
                                Spacer()
                                Button(L10n.text("Комментарии", "Comments")) {
                                    selectedVideo = video
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct VideoCommentsSheet: View {
    let video: VideoDTO
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [VideoCommentDTO] = []
    @State private var text: String = ""
    @State private var replyingTo: VideoCommentDTO?

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.display_name)
                                .font(.caption.bold())
                            Text(comment.deleted ? L10n.text("Комментарий удалён", "Comment deleted") : comment.text)
                                .font(.body)
                                .foregroundColor(comment.deleted ? .secondary : .primary)
                            HStack {
                                if !comment.deleted {
                                    Button(L10n.text("Ответить", "Reply")) {
                                        replyingTo = comment
                                    }
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
                    }
                }
                if !video.comments_locked {
                    HStack {
                        TextField(
                            replyingTo == nil ? L10n.text("Комментарий...", "Comment...") : L10n.text("Ответ...", "Reply..."),
                            text: $text
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
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
                        .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral))
                    }
                    .padding()
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
