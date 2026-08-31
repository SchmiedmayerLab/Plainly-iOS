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

    /// Covers the sources an answer drew on reaching the report.
    ///
    /// The context is built the way the shipping code builds it — a session appends its output and the sources
    /// arrive afterwards to be merged onto it — because `LLMContextEntity/citations` cannot be set from here
    /// directly, and because a test that set it directly would not notice the merge failing to find the answer.
    @Test
    func carriesTheSourcesOfAnAnswer() throws {
        let url = try #require(URL(string: "https://www.spine-health.org/stenosis"))
        var context = LLMContext()
        context.append(userMessage: "What does my MRI show?")
        context.append(assistantOutputDelta: "Moderate central canal stenosis at L4–L5.", isComplete: true)
        context.markAssistantOutputCompleted()
        context.append(citations: [
            .init(title: "Spinal Stenosis", source: .web(url)),
            .init(title: "Lumbar Stenosis Guideline", source: .file(name: "stenosis.pdf"))
        ])

        let messages = context.compactMap(\.studyReportChatMessage)
        let data = try JSONEncoder().encode(messages)
        let encoded = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        #expect(encoded.count == 2)
        #expect(encoded[0]["citations"] == nil, "a question has no sources, so it carries no key at all")

        let citations = try #require(encoded[1]["citations"] as? [[String: Any]])
        #expect(citations.count == 2)
        #expect(citations[0]["title"] as? String == "Spinal Stenosis")
        #expect(citations[0]["url"] as? String == "https://www.spine-health.org/stenosis")
        #expect(citations[0]["file"] == nil, "a source on the web names no file")
        #expect(citations[1]["title"] as? String == "Lumbar Stenosis Guideline")
        #expect(citations[1]["file"] as? String == "stenosis.pdf")
        #expect(citations[1]["url"] == nil, "a source the model was given has no address")
        // A citation's identity is freshly generated, so encoding it would make two identical runs differ.
        #expect(citations.allSatisfy { $0["id"] == nil })
    }
}
