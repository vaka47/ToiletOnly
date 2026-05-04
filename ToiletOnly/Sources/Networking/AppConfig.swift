import Foundation

enum AppConfig {
    private static func configuredURL(
        infoKey: String,
        environmentKey: String,
        defaultValue: String
    ) -> URL? {
        let envValue = ProcessInfo.processInfo.environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let envValue, !envValue.isEmpty {
            return URL(string: envValue)
        }
        let infoValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        if let infoValue, !infoValue.isEmpty {
            return URL(string: infoValue)
        }
        return URL(string: defaultValue)
    }

    static let apiBaseURL = configuredURL(
        infoKey: "API_BASE_URL",
        environmentKey: "API_BASE_URL",
        defaultValue: "http://127.0.0.1:8000"
    )
    static let wsBaseURL = configuredURL(
        infoKey: "WS_BASE_URL",
        environmentKey: "WS_BASE_URL",
        defaultValue: "ws://127.0.0.1:8000"
    )
    static let isLocalDemo: Bool = {
        guard let host = apiBaseURL?.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }()
}
