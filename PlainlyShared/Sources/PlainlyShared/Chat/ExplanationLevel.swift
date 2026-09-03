//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveLLM


/// How much clinical detail the participant wants in an answer.
public enum ExplanationLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case simple
    case balanced
    case detailed

    /// Identifies this instruction in the context, so a change rewrites it rather than adding another.
    public static let instructionID = UUID(uuidString: "5C0B0E24-3E4B-4C0F-9E2E-5B7E4F2A61D3") ?? UUID()

    public var id: Self {
        self
    }

    public var label: LocalizedStringResource {
        switch self {
        case .simple: "Simple"
        case .balanced: "Balanced"
        case .detailed: "Detailed"
        }
    }

    /// What the participant is choosing between, in their words rather than the model's.
    public var explainer: LocalizedStringResource {
        switch self {
        case .simple: "Everyday words, short answers, no medical terms."
        case .balanced: "Plain language, with the medical term named once."
        case .detailed: "The clinical terms and the numbers behind them."
        }
    }

    /// The instruction that carries this choice to the model.
    ///
    /// It reaches every request rather than only the next one: `GroveLLMOpenAI` gathers the system messages in
    /// the context into the request's instructions each time it asks for an answer.
    public var instruction: String {
        switch self {
        case .simple:
            """
            Explanation level: simple. Use everyday words and short sentences. Leave out medical terms, \
            lab names and numbers unless the participant asks for them.
            """
        case .balanced:
            """
            Explanation level: balanced. Explain in plain language, and name the medical term once where \
            it helps the participant recognise it later. Give a number only when it carries the point.
            """
        case .detailed:
            """
            Explanation level: detailed. Use the clinical terms, give the values they refer to, and say \
            what the thresholds around them mean. Keep the sentences readable.
            """
        }
    }
}


extension LLMContext {
    /// Records how detailed the participant wants an answer to be.
    ///
    /// Kept under one identifier so a change rewrites the instruction instead of adding a second one that
    /// contradicts the first. `GroveLLMOpenAI` gathers every system message into each request's instructions,
    /// so the one entity reaches every later answer.
    public mutating func setExplanationLevel(_ level: ExplanationLevel) {
        set(systemMessage: level.instruction, id: ExplanationLevel.instructionID)
    }
}
