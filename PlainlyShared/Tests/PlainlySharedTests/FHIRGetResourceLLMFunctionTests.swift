//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

@testable import PlainlyShared
import Testing


@Suite
struct FHIRGetResourceLLMFunctionTests {
    @Test("Omits an empty resource identifier enum")
    func emptyResourceIdentifierEnum() {
        #expect(FHIRGetResourceLLMFunction.resourceIdentifierEnum([], limit: 250) == nil)
    }

    @Test("Limits the resource identifier enum")
    func limitedResourceIdentifierEnum() {
        #expect(
            FHIRGetResourceLLMFunction.resourceIdentifierEnum(
                ["Observation/first", "Observation/second", "Observation/third"],
                limit: 2
            ) == ["Observation/second", "Observation/third"]
        )
    }
}
