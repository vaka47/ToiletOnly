import Foundation

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func request<T: Decodable>(_ endpoint: String, method: String = "GET", token: String? = nil, body: Encodable? = nil) async throws -> T {
        guard let baseURL = AppConfig.apiBaseURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.timeoutInterval = method == "GET" ? 15 : 30
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard httpResponse.statusCode < 300 else {
            let detail = (try? JSONDecoder().decode(APIErrorPayload.self, from: data))?.detail
            throw APIClientError(statusCode: httpResponse.statusCode, detail: detail)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func upload(request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        try await session.upload(for: request, fromFile: fileURL)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void

    init(_ encodable: Encodable) {
        self.encodeBlock = encodable.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}

private struct APIErrorPayload: Decodable {
    let detail: String?
}

struct APIClientError: LocalizedError {
    let statusCode: Int
    let detail: String?

    var errorDescription: String? {
        guard let detail, !detail.isEmpty else {
            return "HTTP \(statusCode)"
        }
        return detail
    }
}
