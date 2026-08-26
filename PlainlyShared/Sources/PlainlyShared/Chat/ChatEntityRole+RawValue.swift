//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import GroveLLM


extension LLMContextEntity {
    /// Maps a context entity into the chat-message shape used by version 1 study reports.
    ///
    /// The mapping intentionally matches the projection used before the Grove migration. Reasoning summaries are
    /// a presentation detail and are omitted so a dependency update does not silently change the report schema.
    ///
    /// Sources are the one deliberate addition since. The chat shows a participant which documents an answer drew
    /// on, and a report that dropped them left everyone reading the session afterwards — a reviewer grading the
    /// answer most of all — unable to see what the participant saw. The field is additive: it is written only for
    /// an assistant message that has sources, so a report from before it existed reads back unchanged.
    public var studyReportChatMessage: StudyReport.TimelineEvent.ChatMessage? {
        let role: String
        let content: String
        var citations: [StudyReport.TimelineEvent.ChatMessage.Citation] = []
        switch self.role {
        case .system:
            role = "hidden_system"
            content = self.content
        case .user:
            role = "user"
            content = self.content
        case .assistant:
            role = "assistant"
            content = self.content
            citations = (self.citations ?? []).map(\.studyReportCitation)
        case .toolCalls(let toolCalls):
            role = "hidden_assistantToolCall"
            content = toolCalls
                .map { "\($0.id) \($0.name) \($0.arguments)" }
                .joined(separator: "\n")
        case .toolCallResponse:
            role = "hidden_function"
            content = self.content
        case .assistantThinking:
            return nil
        }
        return .init(timestamp: date, role: role, content: content, citations: citations)
    }
}


extension LLMCitation {
    /// The citation, flattened into the shape a study report writes.
    fileprivate var studyReportCitation: StudyReport.TimelineEvent.ChatMessage.Citation {
        switch source {
        case .web(let url):
            .init(title: title, url: url, file: nil)
        case .file(let name):
            .init(title: title, url: nil, file: name)
        }
    }
}
