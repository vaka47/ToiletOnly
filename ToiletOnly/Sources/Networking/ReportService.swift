import Foundation

private struct ReportRequestPayload: Encodable {
    let target_user_id: String
    let report_type: String
    let reason: String?
}

final class ReportService {
    static let shared = ReportService()

    private init() {}

    func report(targetUserId: String, type: String, reason: String?, token: String?) async {
        guard let token else { return }
        let payload = ReportRequestPayload(
            target_user_id: targetUserId,
            report_type: type,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let _: ReportResponse = try await APIClient.shared.request(
                "/reports",
                method: "POST",
                token: token,
                body: payload
            )
        } catch {
            print("Report failed: \(error)")
        }
    }
}

private struct ReportResponse: Decodable {
    let status: String?
}
