import SwiftUI
import AVKit

struct ProfileCardView: View {
    let profile: DatingProfile
    let remainingSuperLikes: Int
    let onSkip: () -> Void
    let onLike: () -> Void
    let onSuperLike: () -> Void
    let onMore: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @GestureState private var dragOffset: CGSize = .zero
    @State private var currentPhotoIndex: Int = 0
    @State private var isExpanded: Bool = false
    @State private var videos: [VideoDTO] = []

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = max(geometry.size.height - 8, 620)
            ZStack(alignment: .bottom) {
                mediaLayer
                    .frame(height: cardHeight)
                    .offset(x: dragOffset.width)
                    .rotationEffect(.degrees(Double(dragOffset.width / 24)))
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: dragOffset)

                topOverlay
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity, alignment: .top)

                gradientOverlay
                    .frame(height: min(cardHeight * 0.52, 360))
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if isExpanded {
                    expandedPanel
                        .padding(.horizontal, 18)
                        .padding(.bottom, 118)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    collapsedCaption
                        .padding(.horizontal, 22)
                        .padding(.bottom, 126)
                        .transition(.opacity)
                }

                actionRow
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: AppTheme.shadow.opacity(0.9), radius: 28, x: 0, y: 18)
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .gesture(cardGesture)
            .onChange(of: profile.id) { _ in
                currentPhotoIndex = 0
                isExpanded = false
            }
            .task(id: profile.id) {
                videos = await VideoService.shared.byUser(userId: profile.remoteUserId, token: authViewModel.token())
            }
        }
        .frame(height: 690)
    }

    private var mediaLayer: some View {
        ZStack {
            currentMedia

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { previousPhoto() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { nextPhoto() }
            }
        }
    }

    @ViewBuilder
    private var currentMedia: some View {
        if let item = mediaItems[safe: currentPhotoIndex] {
            if item.isVideo, let url = URL(string: item.value), url.scheme?.hasPrefix("http") == true {
                VideoPlayer(player: AVPlayer(url: url))
                    .scaledToFill()
            } else {
                CardPhotoView(imageName: item.value, fallbackText: profile.name)
            }
        } else {
            CardPhotoView(imageName: "", fallbackText: profile.name)
        }
    }

    private var topOverlay: some View {
        VStack(spacing: 14) {
            photoDots
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    if profile.isOnline {
                        SessionCountdownPill(expiresAt: profile.sessionExpiresAt, accent: .white)
                    }
                    if let distance = profile.distanceKm {
                        OverlayTag(title: String(format: L10n.text("%.1f км", "%.1f km"), distance))
                    }
                }
                Spacer()
                VStack(spacing: 10) {
                    overlayIcon("info.circle.fill") {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            isExpanded.toggle()
                        }
                    }
                    overlayIcon("xmark.circle.fill") {
                        onMore()
                    }
                }
            }
        }
    }

    private var photoDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index == currentPhotoIndex ? Color.white : Color.white.opacity(0.36))
                    .frame(width: index == currentPhotoIndex ? 20 : 8, height: 4)
            }
        }
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(isExpanded ? 0.22 : 0.38),
                Color.black.opacity(0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var collapsedCaption: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.hideAge ? profile.name : "\(profile.name), \(profile.age)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if profile.isOnline {
                    Circle()
                        .fill(AppTheme.mint)
                        .frame(width: 10, height: 10)
                }
            }

            Text(profile.bio)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)

            if !profile.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profile.tags.prefix(4), id: \.self) { tag in
                            OverlayTag(title: tag)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.text("Профиль", "Profile"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))

                Text(profile.hideAge ? profile.name : "\(profile.name), \(profile.age)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(profile.bio)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.92))

                if !profile.tags.isEmpty {
                    FlexibleTagFlow(tags: profile.tags)
                }

                if !videos.isEmpty {
                    Text(L10n.text("Видео из прошлых сессий", "Past session videos"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(videos) { video in
                                ProfileVideoPreview(video: video)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.56))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            )
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    if value.translation.height > 90 {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isExpanded = false
                        }
                    }
                }
        )
    }

    private var actionRow: some View {
        HStack(spacing: 18) {
            actionButton(icon: "xmark", tint: .white, fill: Color.white.opacity(0.22), size: 68, action: onSkip)
            actionButton(icon: "heart.fill", tint: AppTheme.mango, fill: AppTheme.mango.opacity(0.20), size: 78) {
                onSuperLike()
            }
            .overlay(alignment: .topTrailing) {
                Text("\(remainingSuperLikes)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .offset(x: 6, y: -6)
            }
            actionButton(icon: "heart.fill", tint: .white, fill: AppTheme.coral, size: 68, action: onLike)
        }
    }

    private func actionButton(
        icon: String,
        tint: Color,
        fill: Color,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundColor(tint)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(fill)
                        .background(.ultraThinMaterial, in: Circle())
                )
                .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func overlayIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.28))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($dragOffset) { value, state, _ in
                if isExpanded {
                    state = .zero
                } else {
                    state = value.translation
                }
            }
            .onEnded { value in
                if value.translation.height < -90 {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        isExpanded = true
                    }
                    return
                }
                if value.translation.height > 90 && isExpanded {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        isExpanded = false
                    }
                    return
                }
                if value.translation.width < -110 {
                    onSkip()
                } else if value.translation.width > 110 {
                    onLike()
                }
            }
    }

    private var mediaItems: [ProfileMediaItem] {
        let basePhotos = profile.photos.isEmpty ? [profile.sessionVideoURL].compactMap { $0 } : profile.photos
        if let videoURL = profile.sessionVideoURL, !videoURL.isEmpty {
            return [ProfileMediaItem(value: videoURL, isVideo: true)] + basePhotos.map { ProfileMediaItem(value: $0, isVideo: false) }
        }
        return basePhotos.map { ProfileMediaItem(value: $0, isVideo: false) }
    }

    private func nextPhoto() {
        guard !mediaItems.isEmpty else { return }
        currentPhotoIndex = min(mediaItems.count - 1, currentPhotoIndex + 1)
    }

    private func previousPhoto() {
        guard !mediaItems.isEmpty else { return }
        currentPhotoIndex = max(0, currentPhotoIndex - 1)
    }
}

private struct ProfileMediaItem: Hashable {
    let value: String
    let isVideo: Bool
}

private struct CardPhotoView: View {
    let imageName: String
    let fallbackText: String

    var body: some View {
        if let url = URL(string: imageName), url.scheme?.hasPrefix("http") == true {
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

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.sky.opacity(0.42), AppTheme.coral.opacity(0.34), AppTheme.mango.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                Text(fallbackText)
                    .font(.caption.bold())
            }
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OverlayTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.28))
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct FlexibleTagFlow: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(tags, size: 3), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tag in
                        OverlayTag(title: tag)
                    }
                }
            }
        }
    }

    private func chunked(_ source: [String], size: Int) -> [[String]] {
        stride(from: 0, to: source.count, by: size).map {
            Array(source[$0..<min($0 + size, source.count)])
        }
    }
}

private struct ProfileVideoPreview: View {
    let video: VideoDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = URL(string: video.asset_url) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 180, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text("❤️ \(video.reactions_count)   💬 \(video.comments_count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(width: 180, alignment: .leading)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
