//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLLM
import PlainlyShared
import Testing


struct StudyReportChatMessageTests {
    @Test
    func preservesVersionOneRolesAndToolContent() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let entities = [
            LLMContextEntity(date: date, role: .system, content: "instructions"),
            LLMContextEntity(date: date, role: .user, content: "question"),
            LLMContextEntity(
                date: date,
                role: .toolCalls([.init(id: "call-1", name: "get_resources", arguments: "{\"type\":\"Observation\"}")]),
                content: ""
            ),
            LLMContextEntity(
                date: date,
                role: .toolCallResponse(id: "call-1", name: "get_resources"),
                content: "result"
            ),
            LLMContextEntity(date: date, role: .assistant, content: "answer"),
            LLMContextEntity(date: date, role: .assistantThinking, content: "reasoning summary")
        ]

        let messages = entities.compactMap(\.studyReportChatMessage)
        let data = try JSONEncoder().encode(messages)
        let encoded = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(encoded.compactMap { $0["role"] as? String } == [
            "hidden_system",
            "user",
            "hidden_assistantToolCall",
            "hidden_function",
            "assistant"
        ])
        #expect(encoded[2]["content"] as? String == "call-1 get_resources {\"type\":\"Observation\"}")
        #expect(encoded[3]["content"] as? String == "result")
    }
}
