//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
import class ModelsR4.Questionnaire
import PlainlyShared
import PlainlyStudyDefinitions
import Testing


@Suite
struct PlainlySharedTests {
    @Test(arguments: [
        (AppLaunchMode.standalone, true),
        (.test, true),
        (.study(studyId: nil), false),
        (.study(studyId: "study"), false)
    ])
    func requiresUserProvidedAPIKey(mode: AppLaunchMode, expected: Bool) {
        #expect(mode.requiresUserProvidedAPIKey == expected)
    }

    @Test
    func encryptAndDecrypt() throws {
        let publicKey = try Curve25519.KeyAgreement.PublicKey(
            contentsOf: try #require(Bundle.module.url(forResource: "public_key", withExtension: "pem"))
        )
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(
            contentsOf: try #require(Bundle.module.url(forResource: "private_key", withExtension: "pem"))
        )
        let data = try #require("Hello Spezi :) 🚀🚀🚀🚀🚀🚀🚀".data(using: .utf8))
        let encrypted = try data.encrypted(using: publicKey)
        let decrypted = try encrypted.decrypted(using: privateKey)
        #expect(decrypted == data)
    }
}
