//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

@testable import PlainlyCLI
import Testing


private actor FirebaseAuthTransportStub: FirebaseAuthTransport {
    private(set) var signInCount = 0
    private(set) var refreshCount = 0
    private(set) var lastRefreshToken: String?

    var callCounts: (signIns: Int, refreshes: Int) {
        (signInCount, refreshCount)
    }

    func signInAnonymously(config: FirebaseConfig) async throws -> FirebaseAuthToken {
        signInCount += 1
        return FirebaseAuthToken(
            idToken: "initial-id-token",
            refreshToken: "stable-refresh-token",
            expiresIn: 0
        )
    }

    func refreshToken(_ refreshToken: String, config: FirebaseConfig) async throws -> FirebaseAuthToken {
        refreshCount += 1
        lastRefreshToken = refreshToken
        return FirebaseAuthToken(
            idToken: "refreshed-id-token",
            refreshToken: "stable-refresh-token",
            expiresIn: 3600
        )
    }
}


struct FirebaseAuthTests {
    @Test
    func refreshesTheSameAnonymousSessionInsteadOfSigningUpAgain() async throws {
        let transport = FirebaseAuthTransportStub()
        let auth = FirebaseAuth(
            config: FirebaseConfig(apiKey: "test", projectID: "test"),
            transport: transport
        )

        #expect(try await auth.anonymouslySignIn() == "initial-id-token")
        #expect(try await auth.anonymouslySignIn() == "refreshed-id-token")
        let callCounts = await transport.callCounts
        #expect(callCounts.signIns == 1)
        #expect(callCounts.refreshes == 1)
        #expect(await transport.lastRefreshToken == "stable-refresh-token")
    }
}
