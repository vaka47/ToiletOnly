import Foundation

struct ModerationSummaryDTO: Decodable {
    let open_count: Int
    let reviewing_count: Int
    let resolved_count: Int
    let dismissed_count: Int
}

struct OpsSummaryDTO: Decodable {
    let window_days: Int
    let total_users: Int
    let profiles_completed: Int
    let activated_users: Int
    let session_starts: Int
    let likes_sent: Int
    let superlikes_sent: Int
    let matches_created: Int
    let matches_with_messages: Int
    let kept_matches: Int
    let videos_published: Int
    let profile_completion_rate: Double
    let activation_rate: Double
    let like_to_match_rate: Double
    let match_to_first_message_rate: Double
    let message_to_kept_rate: Double
    let video_publish_rate: Double
    let moderation: ModerationSummaryDTO
}

struct ReportModerationDTO: Decodable, Identifiable {
    let id: String
    let reporter_user_id: String
    let reporter_display_name: String
    let target_user_id: String
    let target_display_name: String
    let report_type: String
    let object_id: String?
    let reason: String?
    let status: String
    let reviewed_at: String?
    let reviewed_note: String?
    let created_at: String
}

private struct ReportModerationUpdateRequest: Encodable {
    let status: String
    let reviewed_note: String?
}

final class OpsService {
    static let shared = OpsService()

    private init() {}

    func summary(windowDays: Int, token: String?) async -> OpsSummaryDTO? {
        guard let token else { return nil }
        do {
            let item: OpsSummaryDTO = try await APIClient.shared.request(
                "/ops/summary?window_days=\(windowDays)",
                token: token
            )
            return item
        } catch {
            print("Ops summary failed: \(error)")
            return nil
        }
    }

    func reports(status: String?, token: String?) async -> [ReportModerationDTO] {
        guard let token else { return [] }
        do {
            let suffix: String
            if let status, !status.isEmpty, status != "all" {
                suffix = "?status=\(status)"
            } else {
                suffix = ""
            }
            let items: [ReportModerationDTO] = try await APIClient.shared.request(
                "/ops/reports\(suffix)",
                token: token
            )
            return items
        } catch {
            print("Ops reports failed: \(error)")
            return []
        }
    }

    func updateReport(
        reportId: String,
        status: String,
        note: String?,
        token: String?
    ) async -> ReportModerationDTO? {
        guard let token else { return nil }
        let payload = ReportModerationUpdateRequest(
            status: status,
            reviewed_note: note?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let item: ReportModerationDTO = try await APIClient.shared.request(
                "/ops/reports/\(reportId)",
                method: "PATCH",
                token: token,
                body: payload
            )
            return item
        } catch {
            print("Ops report update failed: \(error)")
            return nil
        }
    }
}
