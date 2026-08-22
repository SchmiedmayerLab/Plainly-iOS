//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLMOpenAI
import PlainlyShared
import Testing


struct SamplingControlsTests {
    /// The models Plainly may pin that still take a temperature.
    ///
    /// Restated rather than derived, so that changing a model's support is a deliberate two-sided edit rather
    /// than one this test follows silently.
    private static let acceptingModels: Set<String> = [
        "gpt-4o",
        "claude-haiku-4-5",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "Llama-4"
    ]

    @Test("Every model a study may pin answers for sampling")
    func everySupportedModelIsDeliberate() {
        for model in LLMOpenAIParameters.ModelType.plainlySupportedModels {
            #expect(
                model.acceptsSamplingControls == Self.acceptingModels.contains(model.rawValue),
                "\(model.rawValue) neither takes nor refuses sampling deliberately."
            )
        }
    }

    @Test("The models that moved past sampling are known to have")
    func modelsThatRefuseSampling() {
        // The two that broke a deployment: the reasoning model a study pinned, and the Anthropic model whose
        // identifier Grove necessarily reads as an OpenAI one.
        #expect(!LLMOpenAIParameters.ModelType.gpt5_5.acceptsSamplingControls)
        #expect(!LLMOpenAIParameters.ModelType.claudeOpus5.acceptsSamplingControls)
        #expect(!LLMOpenAIParameters.ModelType.claudeSonnet5.acceptsSamplingControls)
    }

    @Test("The models that still take sampling keep it")
    func modelsThatAcceptSampling() {
        #expect(LLMOpenAIParameters.ModelType.gpt4o.acceptsSamplingControls)
        #expect(LLMOpenAIParameters.ModelType.claudeHaiku4_5.acceptsSamplingControls)
        #expect(LLMOpenAIParameters.ModelType.gemini2_5Pro.acceptsSamplingControls)
    }
}
