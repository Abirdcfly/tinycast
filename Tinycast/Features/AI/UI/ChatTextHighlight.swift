import SwiftUI

/// What find is looking for in one message, handed down so every text it draws marks the words.
struct ChatTextHighlight: Equatable {
    let query: String
    /// The match find is on, when it is in this message; only that one takes the solid mark.
    let current: ChatFindOccurrence?

    /// The id the drawn text holding the current match takes, so the transcript can scroll to it.
    static let currentAnchor = "chat-find-current"

    func isCurrent(_ leaf: [Int]) -> Bool { current?.leaf == leaf }

    func attributed(_ string: String, leaf: [Int]) -> AttributedString {
        var text = AttributedString(string)
        apply(to: &text, leaf: leaf)
        return text
    }

    /// Marks every match in place, so Markdown's own runs — code, emphasis — stay as they are.
    func apply(to text: inout AttributedString, leaf: [Int]) {
        let plain = String(text.characters)
        for (index, range) in ChatFindIndex.ranges(of: query, in: plain).enumerated() {
            let start = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            let lower = text.characters.index(text.startIndex, offsetBy: start)
            let upper = text.characters.index(lower, offsetBy: length)
            let solid = current?.leaf == leaf && current?.index == index
            text[lower..<upper].backgroundColor = solid ? Theme.Colors.findCurrent : Theme.Colors.findMatch
            if solid { text[lower..<upper].foregroundColor = Theme.Colors.findCurrentInk }
        }
    }
}

extension View {
    /// Only the view drawing the current match carries the anchor the transcript scrolls to.
    @ViewBuilder
    func findAnchor(_ highlight: ChatTextHighlight?, leaf: [Int]) -> some View {
        if highlight?.isCurrent(leaf) == true {
            id(ChatTextHighlight.currentAnchor)
        } else {
            self
        }
    }
}

private struct ChatTextHighlightKey: EnvironmentKey {
    static let defaultValue: ChatTextHighlight? = nil
}

private struct ChatFindPathKey: EnvironmentKey {
    static let defaultValue: [Int] = []
}

private struct ChatCitationsKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}

private struct ChatExpandsReasoningKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var chatTextHighlight: ChatTextHighlight? {
        get { self[ChatTextHighlightKey.self] }
        set { self[ChatTextHighlightKey.self] = newValue }
    }

    /// Where the enclosing view sits in its message, built the way `ChatFindIndex.leaves` builds it.
    var chatFindPath: [Int] {
        get { self[ChatFindPathKey.self] }
        set { self[ChatFindPathKey.self] = newValue }
    }

    /// A reply's source numbers by URL key; empty everywhere but a finished reply with sources.
    var chatCitations: [String: Int] {
        get { self[ChatCitationsKey.self] }
        set { self[ChatCitationsKey.self] = newValue }
    }

    var chatExpandsReasoning: Bool {
        get { self[ChatExpandsReasoningKey.self] }
        set { self[ChatExpandsReasoningKey.self] = newValue }
    }
}
