//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import GroveLLMOpenAI


extension LLMOpenAIModelParameters {
    /// The parameters used for every Plainly request to the given model.
    ///
    /// Studies rely on responses being as reproducible as the model allows, so sampling is pinned to the lowest
    /// temperature wherever the model still takes one. The models that have moved past sampling refuse the request
    /// outright rather than ignoring the setting, and reproducibility has to come from the prompt there instead.
    public static func deterministic(for model: LLMOpenAIParameters.ModelType) -> Self {
        model.acceptsSamplingControls ? Self(temperature: 0) : Self()
    }
}
