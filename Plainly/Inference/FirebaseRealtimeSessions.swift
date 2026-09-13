//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import FirebaseFunctions
import Foundation
import PlainlyVoice


/// Mints realtime voice sessions through the `realtimeSession` function, so the app never holds inference credentials.
enum FirebaseRealtimeSessions {
    private struct Grant: Decodable {
        struct Session: Decodable {
            let id: String
        }

        enum CodingKeys: String, CodingKey {
            case value
            case baseUrl = "base_url"
            case session
        }

        let value: String
        let baseUrl: URL
        let session: Session
    }

    static func mint(_ request: VoiceSessionRequest, studyId: String) async throws -> VoiceSessionGrant {
        var name = URLComponents()
        name.path = "realtimeSession"
        name.queryItems = [URLQueryItem(name: "studyId", value: studyId)]
        let callable = Functions.functions().httpsCallable(
            name.string ?? "realtimeSession",
            requestAs: String.self,
            responseAs: String.self
        )
        let fields: [String: String?] = [
            "model": request.model,
            "instructions": request.instructions,
            "voice": request.voice,
            "language": request.language
        ]
        let body = try JSONEncoder().encode(fields.compactMapValues { $0 })
        let response = try await callable.call(String(decoding: body, as: UTF8.self))
        let grant = try JSONDecoder().decode(Grant.self, from: Data(response.utf8))
        return VoiceSessionGrant(clientSecret: grant.value, baseUrl: grant.baseUrl, sessionId: grant.session.id)
    }
}
