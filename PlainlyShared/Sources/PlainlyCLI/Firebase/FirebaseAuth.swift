//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation


struct FirebaseAuthToken: Sendable {
    let idToken: String
    let refreshToken: String
    let expiresIn: Int
}

protocol FirebaseAuthTransport: Sendable {
    func signInAnonymously(config: FirebaseConfig) async throws -> FirebaseAuthToken
    func refreshToken(_ refreshToken: String, config: FirebaseConfig) async throws -> FirebaseAuthToken
}

private struct URLSessionFirebaseAuthTransport: FirebaseAuthTransport {
    func signInAnonymously(config: FirebaseConfig) async throws -> FirebaseAuthToken {
        let url = try endpoint(
            host: "identitytoolkit.googleapis.com",
            path: "/v1/accounts:signUp",
            config: config
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let json = try await response(to: request)
        return try token(
            from: json,
            idTokenKey: "idToken",
            refreshTokenKey: "refreshToken",
            expiresInKey: "expiresIn"
        )
    }

    func refreshToken(_ refreshToken: String, config: FirebaseConfig) async throws -> FirebaseAuthToken {
        let url = try endpoint(
            host: "securetoken.googleapis.com",
            path: "/v1/token",
            config: config
        )
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let json = try await response(to: request)
        return try token(
            from: json,
            idTokenKey: "id_token",
            refreshTokenKey: "refresh_token",
            expiresInKey: "expires_in"
        )
    }

    private func endpoint(host: String, path: String, config: FirebaseConfig) throws -> URL {
        var components = URLComponents()
        components.scheme = config.authEmulatorAddress == nil ? "https" : "http"
        if let address = config.authEmulatorAddress {
            let parts = address.split(separator: ":", maxSplits: 1)
            components.host = String(parts[0])
            components.port = parts.count == 2 ? Int(parts[1]) : nil
            components.path = "/\(host)\(path)"
        } else {
            components.host = host
            components.path = path
        }
        components.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func response(to request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FirebaseConfigError("Firebase authentication failed.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseConfigError("Firebase authentication returned an invalid response.")
        }
        return json
    }

    private func token(
        from json: [String: Any],
        idTokenKey: String,
        refreshTokenKey: String,
        expiresInKey: String
    ) throws -> FirebaseAuthToken {
        guard let idToken = json[idTokenKey] as? String,
              let refreshToken = json[refreshTokenKey] as? String else {
            throw FirebaseConfigError("Firebase authentication returned incomplete credentials.")
        }
        let expiresIn = (json[expiresInKey] as? String).flatMap(Int.init) ?? 3600
        return FirebaseAuthToken(
            idToken: idToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn
        )
    }
}


actor FirebaseAuth {
    let config: FirebaseConfig

    private let transport: any FirebaseAuthTransport
    private var cachedToken: String?
    private var cachedRefreshToken: String?
    private var tokenExpiry: Date = .distantPast

    init(
        config: FirebaseConfig,
        transport: any FirebaseAuthTransport = URLSessionFirebaseAuthTransport()
    ) {
        self.config = config
        self.transport = transport
    }

    /// The current token for this session's anonymous user, signing that user in on the first call.
    ///
    /// Later calls refresh the same user rather than signing up again: a second sign-up is a second
    /// principal, and the chat function only continues stored responses for the one that created them.
    func anonymouslySignIn() async throws -> String {
        if let token = cachedToken, tokenExpiry > Date.now.addingTimeInterval(300) {
            return token
        }
        let token = if let cachedRefreshToken {
            try await transport.refreshToken(cachedRefreshToken, config: config)
        } else {
            try await transport.signInAnonymously(config: config)
        }
        cachedToken = token.idToken
        cachedRefreshToken = token.refreshToken
        tokenExpiry = Date.now.addingTimeInterval(TimeInterval(token.expiresIn))
        return token.idToken
    }
}
