import Foundation

struct ProfileSetupRequest: Encodable {
    let age: Int
    let gender: String
    let hide_age: Bool
    let display_name: String
    let bio_text: String
    let tone: String
    let interests: [String]
    let looking_for_genders: [String]
    let toilet_selfie_url: String
    let photos: [String]
    let consent_photo_ai: Bool
}

struct ProfileSetupResponse: Decodable {
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
}

final class ProfileSetupService {
    static let shared = ProfileSetupService()

    private init() {}

    func setup(token: String?, request: ProfileSetupRequest) async -> ProfileSetupResponse? {
        guard let token else { return nil }
        do {
            let response: ProfileSetupResponse = try await APIClient.shared.request("/profiles/setup", method: "POST", token: token, body: request)
            return response
        } catch {
            print("Profile setup failed: \(error)")
            return nil
        }
    }
}
