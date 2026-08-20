//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import PlainlyShared
import Testing


struct StudyChatResponsesRequestMetadataTests {
    /// The health-record tool is what separates the participant's chat from Plainly's own prompts, which
    /// is what decides whether a request may pull study documents into its instructions.
    @Test
    func theHealthRecordToolMarksARequestAsTheParticipantsChat() throws {
        let chat = try StudyChatResponsesRequestMetadata(body: requestBody(
            input: [["type": "message", "role": "user", "content": "What do my records show?"]],
            tools: [["type": "function", "name": FHIRGetResourceLLMTool.toolName]]
        ))
        let summary = try StudyChatResponsesRequestMetadata(body: requestBody(
            input: [["type": "message", "role": "user", "content": "Summarize this resource."]]
        ))

        #expect(chat.isStudyChatRequest)
        #expect(!summary.isStudyChatRequest)
    }

    /// A tool continuation is still the participant's chat, even though it carries no message of theirs.
    @Test
    func aToolContinuationStaysPartOfTheChat() throws {
        let metadata = try StudyChatResponsesRequestMetadata(body: requestBody(
            input: [["type": "function_call_output", "call_id": "call-1", "output": "Summary"]],
            tools: [["type": "function", "name": FHIRGetResourceLLMTool.toolName]],
            previousResponseID: "resp-question"
        ))

        #expect(metadata.isStudyChatRequest)
    }

    @Test(arguments: [true, false])
    func theRequestSaysWhetherItExpectsAStream(streaming: Bool) throws {
        let metadata = try StudyChatResponsesRequestMetadata(body: requestBody(
            input: [["type": "message", "role": "user", "content": "Hello"]],
            stream: streaming
        ))

        #expect(metadata.usesStreaming == streaming)
    }

    @Test
    func aBodyThatIsNotAJSONObjectIsRejected() {
        #expect(throws: StudyChatResponsesRequestMetadataError.self) {
            try StudyChatResponsesRequestMetadata(body: "not json")
        }
    }

    private func requestBody(
        input: [[String: Any]],
        tools: [[String: Any]] = [],
        stream: Bool = false,
        previousResponseID: String? = nil
    ) throws -> String {
        var body: [String: Any] = ["model": "gpt-5.5", "input": input, "tools": tools, "stream": stream]
        body["previous_response_id"] = previousResponseID
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return try #require(String(data: data, encoding: .utf8))
    }
}
