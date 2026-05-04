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
        request.timeoutInterval = 300

        let bodyFileURL = try makeMultipartBodyFile(
            sourceFileURL: fileURL,
            mimeType: mimeType,
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        let (data, response) = try await APIClient.shared.upload(request: request, fromFile: bodyFileURL)
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

    private func makeMultipartBodyFile(
        sourceFileURL: URL,
        mimeType: String,
        boundary: String
    ) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload_\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        let filename = sourceFileURL.lastPathComponent
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        try handle.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        let sourceHandle = try FileHandle(forReadingFrom: sourceFileURL)
        defer { try? sourceHandle.close() }
        while true {
            let chunk = sourceHandle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty {
                break
            }
            try handle.write(contentsOf: chunk)
        }

        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return tempURL
    }
}

enum UploadError: Error {
    case nsfwDetected
    case faceRequired
}
