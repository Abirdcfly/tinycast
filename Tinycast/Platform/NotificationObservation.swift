import Foundation

/// Notification registrations held as one value. A token is not `Sendable`, so an owner that is
/// an actor cannot touch it from `deinit`; this box cancels them when it goes away.
final class NotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let tokens: [NSObjectProtocol]

    init(center: NotificationCenter = .default, tokens: [NSObjectProtocol]) {
        self.center = center
        self.tokens = tokens
    }

    deinit {
        for token in tokens { center.removeObserver(token) }
    }
}
