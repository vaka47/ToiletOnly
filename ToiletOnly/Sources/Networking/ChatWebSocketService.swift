import Foundation

final class ChatWebSocketService {
    static let shared = ChatWebSocketService()

    private init() {}

    func connect(matchId: String, token: String?, onMessage: @escaping (String) -> Void) -> URLSessionWebSocketTask? {
        guard let baseURL = AppConfig.wsBaseURL else { return nil }
        let url = baseURL.appendingPathComponent("/ws/chat/\(matchId)")
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()

        func receiveNext() {
            task.receive { result in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        onMessage(Self.extractText(from: text) ?? text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            onMessage(Self.extractText(from: text) ?? text)
                        }
                    @unknown default:
                        break
                    }
                    receiveNext()
                case .failure:
                    break
                }
            }
        }

        receiveNext()
        return task
    }

    func send(task: URLSessionWebSocketTask?, text: String) {
        task?.send(.string(text)) { _ in }
    }

    private static func extractText(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["text"] as? String
    }
}
