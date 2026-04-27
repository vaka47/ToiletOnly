import Foundation

struct ProfileCardDTO: Decodable {
    let user_id: String
    let display_name: String
    let age: Int
    let hide_age: Bool
    let gender: String
    let bio_ai: String
    let bio_text: String
    let interests: [String]
    let looking_for_genders: [String]
    let toilet_selfie_url: String
    let photos: [String]
    let session_video_url: String?
    let is_online_toilet: Bool
    let distance_km: Double?
    let session_expires_at: String?
}

struct ProfileOutDTO: Decodable {
    let user_id: String
    let display_name: String
    let age: Int
    let hide_age: Bool
    let gender: String
    let bio_ai: String
    let bio_text: String
    let tone: String
    let interests: [String]
    let looking_for_genders: [String]
    let toilet_selfie_url: String
    let photos: [String]
    let session_video_url: String?
    let session_expires_at: String?
}

struct LocationUpdateRequest: Encodable {
    let lat: Double
    let lon: Double
}

struct SessionVideoRequest: Encodable {
    let asset_url: String
    let caption: String
}

struct SessionStateRequest: Encodable {
    let active: Bool
}

struct SessionStateResponse: Decodable {
    let ok: Bool
    let consumed_matches: Int?
}

final class ProfileService {
    static let shared = ProfileService()

    private init() {}

    func fetchFeed(
        token: String?,
        minAge: Int? = nil,
        maxAge: Int? = nil,
        showNearby: Bool? = nil,
        targetGender: String? = nil,
        radiusKm: Double? = nil
    ) async -> [ProfileCardDTO] {
        guard let token else { return [] }
        do {
            var params: [String] = []
            if let minAge { params.append("age_min=\(minAge)") }
            if let maxAge { params.append("age_max=\(maxAge)") }
            if let showNearby { params.append("show_nearby=\(showNearby)") }
            if let targetGender, !targetGender.isEmpty, targetGender != "any" { params.append("target_gender=\(targetGender)") }
            if let radiusKm { params.append("radius_km=\(String(format: "%.1f", radiusKm))") }
            let suffix = params.isEmpty ? "" : "?\(params.joined(separator: "&"))"
            let items: [ProfileCardDTO] = try await APIClient.shared.request("/profiles/feed\(suffix)", token: token)
            return items
        } catch {
            print("Feed fetch failed: \(error)")
            return []
        }
    }

    func fetchProfile(userId: String, token: String?) async -> ProfileOutDTO? {
        guard let token else { return nil }
        do {
            let item: ProfileOutDTO = try await APIClient.shared.request("/profiles/user/\(userId)", token: token)
            return item
        } catch {
            print("Profile fetch failed: \(error)")
            return nil
        }
    }

    func updateLocation(token: String?, lat: Double, lon: Double) async {
        guard let token else { return }
        let payload = LocationUpdateRequest(lat: lat, lon: lon)
        do {
            let _: [String: Bool] = try await APIClient.shared.request(
                "/profiles/location",
                method: "POST",
                token: token,
                body: payload
            )
        } catch {
            print("Location update failed: \(error)")
        }
    }

    func updateSessionVideo(token: String?, assetURL: String, caption: String) async {
        guard let token else { return }
        let payload = SessionVideoRequest(asset_url: assetURL, caption: caption)
        do {
            let _: [String: Bool] = try await APIClient.shared.request(
                "/profiles/session-video",
                method: "POST",
                token: token,
                body: payload
            )
        } catch {
            print("Session video update failed: \(error)")
        }
    }

    func updateSessionState(token: String?, active: Bool) async {
        guard let token else { return }
        let payload = SessionStateRequest(active: active)
        do {
            let _: SessionStateResponse = try await APIClient.shared.request(
                "/profiles/session-state",
                method: "POST",
                token: token,
                body: payload
            )
        } catch {
            print("Session state update failed: \(error)")
        }
    }

    func deleteMyProfile(token: String?) async -> Bool {
        guard let token else { return false }
        do {
            let _: EmptyResponse = try await APIClient.shared.request(
                "/profiles/me",
                method: "DELETE",
                token: token
            )
            return true
        } catch {
            print("Delete profile failed: \(error)")
            return false
        }
    }
}

private struct EmptyResponse: Decodable {
    let ok: Bool?
}
