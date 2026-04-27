import Foundation
import Combine

final class SessionManager: ObservableObject {
    enum State {
        case locked
        case active(expiresAt: Date)
    }

    @Published private(set) var state: State = .locked

    private var expirationTimer: AnyCancellable?
    private(set) var lastToiletDetectedAt: Date?

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var expiresAt: Date? {
        if case let .active(expiresAt) = state { return expiresAt }
        return nil
    }

    func startSession(durationMinutes: Int = 15) {
        let expiresAt = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        state = .active(expiresAt: expiresAt)
        scheduleExpiration(at: expiresAt)
    }

    func endSession() {
        state = .locked
        lastToiletDetectedAt = nil
        expirationTimer?.cancel()
        expirationTimer = nil
    }

    func refresh() {
        guard case let .active(expiresAt) = state else { return }
        if Date() >= expiresAt {
            endSession()
        }
    }

    func markToiletDetected() {
        lastToiletDetectedAt = Date()
    }

    var isToiletGateOpen: Bool {
        guard let lastToiletDetectedAt else { return false }
        return Date().timeIntervalSince(lastToiletDetectedAt) < 20
    }

    private func scheduleExpiration(at date: Date) {
        expirationTimer?.cancel()
        let interval = max(0, date.timeIntervalSinceNow)
        expirationTimer = Just(())
            .delay(for: .seconds(interval), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.endSession()
            }
    }
}
