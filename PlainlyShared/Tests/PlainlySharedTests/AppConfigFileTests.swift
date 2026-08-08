//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import PlainlyShared
import Testing


@Suite
struct AppConfigFileTests {
    @Test
    func completeFirebaseConfigurationIsValid() throws {
        let config = try firebaseConfiguration(apiKey: #""api-key""#)

        #expect(config.missingRequiredKeys.isEmpty)
    }

    @Test(arguments: [#""""#, #""   ""#, "true"])
    func invalidRequiredFirebaseValuesAreReported(apiKey: String) throws {
        let config = try firebaseConfiguration(apiKey: apiKey)

        #expect(config.missingRequiredKeys == ["API_KEY"])
    }

    @Test
    func missingRequiredFirebaseValueIsReported() throws {
        let config = try firebaseConfiguration(apiKey: nil)

        #expect(config.missingRequiredKeys == ["API_KEY"])
    }

    private func firebaseConfiguration(apiKey: String?) throws -> AppConfigFile.FirebaseConfigDictionary {
        let apiKeyEntry = apiKey.map { #""API_KEY": \#($0),"# } ?? ""
        let data = Data(
            """
            {
                \(apiKeyEntry)
                "BUNDLE_ID": "edu.stanford.llmonfhir",
                "GCM_SENDER_ID": "sender",
                "GOOGLE_APP_ID": "app",
                "PLIST_VERSION": "1",
                "PROJECT_ID": "project",
                "STORAGE_BUCKET": "bucket"
            }
            """.utf8
        )
        return try JSONDecoder().decode(AppConfigFile.FirebaseConfigDictionary.self, from: data)
    }
}
