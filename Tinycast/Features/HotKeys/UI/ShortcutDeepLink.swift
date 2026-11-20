import SwiftUI

/// Copy Deeplink on a shortcut field. Only Settings sets it, so onboarding's field offers nothing.
struct ShortcutDeepLink: Sendable {
    let url: @MainActor @Sendable (HotKeyAction) -> URL?
    let copy: @MainActor @Sendable (URL) -> Void
}

private struct ShortcutDeepLinkKey: EnvironmentKey {
    static let defaultValue: ShortcutDeepLink? = nil
}

extension EnvironmentValues {
    var shortcutDeepLink: ShortcutDeepLink? {
        get { self[ShortcutDeepLinkKey.self] }
        set { self[ShortcutDeepLinkKey.self] = newValue }
    }
}
