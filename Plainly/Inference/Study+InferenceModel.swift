//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLMOpenAI
import PlainlyShared


extension Study {
    /// The model this study's inference requests ask for.
    ///
    /// A local emulator run may be pointed at a different one, because a development gateway key is rarely
    /// entitled to every model a deployment uses. Every other run gets the model the study pins.
    var inferenceModel: LLMOpenAIParameters.ModelType {
        guard let override = FeatureFlags.llmModelOverride else {
            return llmModel
        }
        return .init(rawValue: override)
    }
}
