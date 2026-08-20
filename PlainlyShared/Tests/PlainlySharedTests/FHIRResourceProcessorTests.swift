//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLM
@testable import PlainlyShared
import Testing


struct FHIRResourceProcessorTests {
    @Test
    func responseRequestPreservesInstructionsAndContainsUserInput() {
        let context = FHIRResourceProcessor<String>.inferenceContext(prompt: "Summarize this resource.")

        #expect(context.count == 2)
        #expect(context.first?.role == .system)
        #expect(context.first?.content == "Summarize this resource.")
        #expect(context.last?.role == .user)
        #expect(context.last?.content == "Produce the requested resource summary now.")
    }
}
