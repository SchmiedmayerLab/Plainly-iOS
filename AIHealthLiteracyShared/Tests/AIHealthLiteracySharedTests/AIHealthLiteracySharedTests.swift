//
// This source file is part of the Stanford AI Health Literacy iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import AIHealthLiteracyShared
import AIHealthLiteracyStudyDefinitions
import CryptoKit
import Foundation
import class ModelsR4.Questionnaire
import Testing


@Suite
struct AIHealthLiteracySharedTests {
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
