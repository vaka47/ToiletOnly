import Foundation

struct MediaUploadResponse: Decodable {
    let asset_url: String
}

final class MediaService {
    static let shared = MediaService()

    private init() {}

    func uploadVideo(token: String?, fileURL: URL, purpose: String = "session_video") async throws -> String {
        let ext = fileURL.pathExtension.lowercased()
        let mimeType: String
        switch ext {
        case "mov":
            mimeType = "video/quicktime"
        case "m4v":
            mimeType = "video/x-m4v"
        default:
            mimeType = "video/mp4"
        }
        return try await uploadMedia(token: token, fileURL: fileURL, mimeType: mimeType, purpose: purpose)
    }

    func uploadImage(token: String?, fileURL: URL, purpose: String = "profile_photo") async throws -> String {
        try await uploadMedia(token: token, fileURL: fileURL, mimeType: "image/jpeg", purpose: purpose)
    }

    private func uploadMedia(token: String?, fileURL: URL, mimeType: String, purpose: String) async throws -> String {
        guard let token, let baseURL = AppConfig.apiBaseURL else { throw URLError(.badURL) }
        var components = URLComponents(url: baseURL.appendingPathComponent("/media/upload"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "purpose", value: purpose)]
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 400 {
            if let payload = String(data: data, encoding: .utf8),
               payload.contains("nsfw_detected") {
                throw UploadError.nsfwDetected
            } else if let payload = String(data: data, encoding: .utf8),
                      payload.contains("face_required") {
                throw UploadError.faceRequired
            }
        }
        guard httpResponse.statusCode < 300 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(MediaUploadResponse.self, from: data)
        return decoded.asset_url
    }
}

enum UploadError: Error {
    case nsfwDetected
    case faceRequired
}
