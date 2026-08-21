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
    public var studyReportChatMessage: StudyReport.TimelineEvent.ChatMessage? {
        let role: String
        let content: String
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
        return .init(timestamp: date, role: role, content: content)
    }
}
