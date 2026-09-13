//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLMOpenAI


/// The one tool a voice session has: hands the participant's turn to the text conversation and returns its answer.
///
/// Its name and parameter are a contract with the backend that pins the session.
struct VoiceForwardingTool: LLMTool {
    let name: String
    let description = "Forwards the participant's spoken question to the assistant and returns its answer."

    @Parameter(description: "The participant's question, in their own words.") var question: String

    private let forward: @Sendable (String) async throws -> String


    init(name: String, forward: @escaping @Sendable (String) async throws -> String) {
        self.name = name
        self.forward = forward
    }


    func execute() async throws -> String? {
        try await forward(question)
    }
}
