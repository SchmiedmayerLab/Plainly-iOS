//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import GroveLLMOpenAI


extension LLMOpenAIModelParameters {
    /// The parameters used for every Plainly request.
    ///
    /// Studies rely on responses being as reproducible as the model allows, so sampling is pinned to
    /// the lowest temperature rather than the provider's default.
    public static let deterministic = Self(temperature: 0)
}
