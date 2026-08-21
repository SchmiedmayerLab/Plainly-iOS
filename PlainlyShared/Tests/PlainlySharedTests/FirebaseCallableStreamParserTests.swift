//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

@testable import PlainlyCLI
import Testing


struct FirebaseCallableStreamParserTests {
    @Test
    func forwardsMessagesAndRequiresTerminalResult() throws {
        var parser = FirebaseCallableStreamParser()

        #expect(try parser.consume("data: {\"message\":\"data: event\\n\\n\"}") == "data: event\n\n")
        #expect(try parser.consume("data: {\"result\":null}") == nil)
        #expect(parser.receivedTerminalResult)
        #expect(throws: Never.self) {
            try parser.finish()
        }
    }

    @Test
    func rejectsErrorAfterMessage() throws {
        var parser = FirebaseCallableStreamParser()

        #expect(try parser.consume("data: {\"message\":\"partial\"}") == "partial")
        #expect(throws: FirebaseCallableStreamError.self) {
            try parser.consume("data: {\"error\":{\"status\":\"INTERNAL\"}}")
        }
    }

    @Test
    func rejectsTruncatedStream() {
        let parser = FirebaseCallableStreamParser()

        #expect(throws: FirebaseCallableStreamError.self) {
            try parser.finish()
        }
    }
}
