import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var displayName: String = ""
    @State private var age: Int = 20
    @State private var gender: String = "unknown"
    @State private var hideAge: Bool = false
    @State private var lookingFor: [String] = []
    @State private var bioText: String = ""
    @State private var tone: String = "meme"
    @State private var interestsText: String = L10n.text("мемы, чат, вайб", "memes, chats, vibe")
    @State private var selfieURL: String = ""
    @State private var additionalItems: [PhotosPickerItem] = []
    @State private var additionalPhotoURLs: [String] = []
    @State private var showSelfieCapture: Bool = false
    @State private var isSaving: Bool = false
    @State private var isUploading: Bool = false
    @State private var showNSFWAlert: Bool = false
    @State private var showFaceAlert: Bool = false
    @State private var showToiletGateAlert: Bool = false

    private let existingProfile: ProfileOutDTO?
    let onComplete: () -> Void

    init(existingProfile: ProfileOutDTO? = nil, onComplete: @escaping () -> Void) {
        self.existingProfile = existingProfile
        self.onComplete = onComplete
        if let profile = existingProfile {
            _displayName = State(initialValue: profile.display_name)
            _age = State(initialValue: profile.age)
            _gender = State(initialValue: profile.gender)
            _hideAge = State(initialValue: profile.hide_age)
            _lookingFor = State(initialValue: profile.looking_for_genders)
            _bioText = State(initialValue: profile.bio_text)
            _tone = State(initialValue: profile.tone)
            _interestsText = State(initialValue: profile.interests.joined(separator: ", "))
            _selfieURL = State(initialValue: profile.toilet_selfie_url)
            _additionalPhotoURLs = State(initialValue: profile.photos)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Профиль", "Profile"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)

                textSection(
                    title: L10n.text("База", "Basics"),
                    subtitle: L10n.text("Имя, возраст и кого показывать в ленте.", "Name, age, and who should appear in your feed.")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        field(title: L10n.text("Имя", "Name")) {
                            TextField("ToiletUser", text: $displayName)
                                .textInputAutocapitalization(.words)
                        }
                        field(title: L10n.text("Возраст", "Age")) {
                            Stepper("\(age)", value: $age, in: 18...60)
                        }
                        Toggle(L10n.text("Скрыть возраст в анкете", "Hide age in profile"), isOn: $hideAge)
                            .tint(AppTheme.coral)
                        field(title: L10n.text("Твой гендер", "Your gender")) {
                            genderRow(selection: $gender)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("Показывать мне", "Show me"))
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                filterChip("male", title: L10n.text("Мужчин", "Men"))
                                filterChip("female", title: L10n.text("Женщин", "Women"))
                                filterChip("other", title: L10n.text("Другое", "Other"))
                            }
                        }
                    }
                }

                textSection(
                    title: L10n.text("Описание", "Description"),
                    subtitle: L10n.text("Коротко и без кринжа.", "Short, clear, and attractive.")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        field(title: L10n.text("Тон профиля", "Profile tone")) {
                            Picker("tone", selection: $tone) {
                                Text("meme").tag("meme")
                                Text("flirty").tag("flirty")
                                Text("chill").tag("chill")
                                Text("nerdy").tag("nerdy")
                            }
                            .pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("Био", "Bio"))
                                .font(.subheadline.weight(.semibold))
                            TextEditor(text: $bioText)
                                .frame(minHeight: 110)
                                .padding(8)
                                .background(Color.white.opacity(0.86))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        field(title: L10n.text("Интересы", "Interests")) {
                            TextField(L10n.text("мемы, кино, спонтанность", "memes, movies, spontaneity"), text: $interestsText)
                        }
                    }
                }

                textSection(
                    title: L10n.text("Фото", "Photos"),
                    subtitle: L10n.text("Toilet selfie нужен при создании и делается только в открытой сессии.", "Toilet selfie is required on creation and only works during an active session.")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            if sessionManager.isActive && sessionManager.isToiletGateOpen {
                                showSelfieCapture = true
                            } else {
                                showToiletGateAlert = true
                            }
                        } label: {
                            mediaTile(
                                title: selfieURL.isEmpty ? L10n.text("Сделать toilet selfie", "Take toilet selfie") : L10n.text("Переснять toilet selfie", "Retake toilet selfie"),
                                subtitle: sessionManager.isActive ? L10n.text("Сессия открыта", "Session is active") : L10n.text("Сначала открой сессию по унитазу", "Open a session by scanning a toilet first"),
                                accent: AppTheme.mint
                            )
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(
                            selection: $additionalItems,
                            maxSelectionCount: max(0, 10 - additionalPhotoURLs.count),
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            mediaTile(
                                title: L10n.text("Добавить фото", "Add photos"),
                                subtitle: L10n.text("До 10 фото", "Up to 10 photos"),
                                accent: AppTheme.sky
                            )
                        }
                        .disabled(additionalPhotoURLs.count >= 10)

                        if !additionalPhotoURLs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(additionalPhotoURLs, id: \.self) { url in
                                        RemovableThumb(urlString: url) {
                                            additionalPhotoURLs.removeAll { $0 == url }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Button(isSaving ? L10n.text("Сохраняем...", "Saving...") : L10n.text("Сохранить профиль", "Save profile")) {
                    Task { await saveProfile() }
                }
                .buttonStyle(PrimaryButtonStyle(tint: AppTheme.coral, useGradient: true))
                .disabled(isSaving || (existingProfile == nil && selfieURL.isEmpty))
            }
            .padding(20)
        }
        .background(AppBackground().ignoresSafeArea())
        .sheet(isPresented: $showSelfieCapture) {
            SelfieCaptureView { data in
                Task { await uploadToiletSelfie(data: data) }
            }
        }
        .onChange(of: additionalItems) { items in
            Task { await uploadAdditional(items: items) }
        }
        .alert(L10n.text("Фото не прошло модерацию", "Photo failed moderation"), isPresented: $showNSFWAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L10n.text("Похоже, там есть запрещенный контент.", "The image appears to contain restricted content."))
        }
        .alert(L10n.text("Нужно лицо", "Face required"), isPresented: $showFaceAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L10n.text("Нужна фотография, где видно лицо.", "A visible face is required."))
        }
        .alert(L10n.text("Нужен унитаз в кадре", "Toilet required in frame"), isPresented: $showToiletGateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L10n.text("Сначала открой сессию, наведя камеру на настоящий унитаз.", "First open a session by pointing the camera at a real toilet."))
        }
    }

    private func saveProfile() async {
        isSaving = true
        let req = ProfileSetupRequest(
            age: age,
            gender: gender,
            hide_age: hideAge,
            display_name: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ToiletUser" : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bio_text: bioText,
            tone: tone,
            interests: interestsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            looking_for_genders: lookingFor,
            toilet_selfie_url: selfieURL,
            photos: Array(additionalPhotoURLs.prefix(10)),
            consent_photo_ai: true
        )
        _ = await ProfileSetupService.shared.setup(token: authViewModel.token(), request: req)
        isSaving = false
        onComplete()
    }

    private func uploadToiletSelfie(data: Data) async {
        guard sessionManager.isActive else { return }
        guard sessionManager.isToiletGateOpen else {
            showToiletGateAlert = true
            return
        }
        isUploading = true
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: tempURL)
            let url = try await MediaService.shared.uploadImage(token: authViewModel.token(), fileURL: tempURL, purpose: "toilet_selfie")
            selfieURL = url
        } catch UploadError.nsfwDetected {
            showNSFWAlert = true
        } catch UploadError.faceRequired {
            showFaceAlert = true
        } catch {}
        isUploading = false
    }

    private func uploadAdditional(items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploading = true
        var urls: [String] = []
        for item in items {
            if additionalPhotoURLs.count + urls.count >= 10 { break }
            if let url = await uploadPickerItem(item: item) {
                urls.append(url)
            }
        }
        additionalPhotoURLs.append(contentsOf: urls)
        additionalItems = []
        isUploading = false
    }

    private func uploadPickerItem(item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: tempURL)
        } catch {
            return nil
        }
        do {
            return try await MediaService.shared.uploadImage(token: authViewModel.token(), fileURL: tempURL, purpose: "profile_photo")
        } catch UploadError.nsfwDetected {
            showNSFWAlert = true
            return nil
        } catch UploadError.faceRequired {
            showFaceAlert = true
            return nil
        } catch {
            return nil
        }
    }

    private func textSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(AppTheme.muted)
                content()
            }
        }
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func genderRow(selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            genderButton(selection: selection, value: "male", title: L10n.text("Мужчина", "Male"))
            genderButton(selection: selection, value: "female", title: L10n.text("Женщина", "Female"))
            genderButton(selection: selection, value: "other", title: L10n.text("Другое", "Other"))
        }
    }

    private func genderButton(selection: Binding<String>, value: String, title: String) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selection.wrappedValue == value ? AppTheme.coral.opacity(0.18) : Color.white.opacity(0.82))
                .foregroundColor(selection.wrappedValue == value ? AppTheme.coral : AppTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ value: String, title: String) -> some View {
        Button {
            if lookingFor.contains(value) {
                lookingFor.removeAll { $0 == value }
            } else if lookingFor.count < 3 {
                lookingFor.append(value)
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(lookingFor.contains(value) ? AppTheme.sky.opacity(0.16) : Color.white.opacity(0.82))
                .foregroundColor(lookingFor.contains(value) ? AppTheme.sky : AppTheme.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func mediaTile(title: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundColor(accent)
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                Spacer()
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RemoteThumb: View {
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 96, height: 128)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct RemovableThumb: View {
    let urlString: String
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RemoteThumb(urlString: urlString)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.coral)
                    .clipShape(Circle())
            }
            .offset(x: 6, y: -6)
        }
    }
}
