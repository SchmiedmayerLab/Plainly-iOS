//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import PlainlyShared


struct FirebaseCallableStreamError: Error, CustomStringConvertible {
    let description: String
}


struct FirebaseCallableStreamParser {
    private(set) var receivedTerminalResult = false

    mutating func consume(_ line: String) throws -> String? {
        guard line.hasPrefix("data: ") else {
            return nil
        }
        guard let jsonData = String(line.dropFirst(6)).data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw FirebaseCallableStreamError(description: "Firebase chat function returned malformed stream data")
        }
        if json["error"] != nil {
            throw FirebaseCallableStreamError(description: "Firebase chat function returned an error")
        }
        if json.keys.contains("message") {
            let message = json["message"]
            if message is NSNull {
                return nil
            }
            guard let message = message as? String else {
                throw FirebaseCallableStreamError(description: "Firebase chat function returned an invalid message")
            }
            return message
        }
        if json.keys.contains("result") {
            receivedTerminalResult = true
            guard json["result"] is NSNull else {
                throw FirebaseCallableStreamError(description: "Firebase chat function returned an unexpected result")
            }
        }
        return nil
    }

    func finish() throws {
        guard receivedTerminalResult else {
            throw FirebaseCallableStreamError(description: "Firebase chat function ended without a terminal result")
        }
    }
}


struct FirebaseChatInterceptor: ClientMiddleware, Sendable {
    private struct MiddlewareError: Error, CustomStringConvertible {
        let description: String
    }

    private let auth: FirebaseAuth
    private let firebaseConfig: FirebaseConfig
    private let studyId: String
    private let chatFunctionName: String
    private let ragEnabled: Bool

    /// The study's dispatch settings are copied rather than retained, because `Study` is not `Sendable`.
    init(
        firebaseConfig: FirebaseConfig,
        study: Study
    ) {
        self.auth = FirebaseAuth(config: firebaseConfig)
        self.firebaseConfig = firebaseConfig
        self.studyId = study.id
        self.chatFunctionName = study.chatFunctionName
        self.ragEnabled = study.ragEnabled
    }
    
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable @concurrent (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let maxBodySize = 7 * 1024 * 1024 // 7 MB
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let data = try await body?.data(upTo: maxBodySize),
              let input = String(bytes: data, encoding: .utf8) else {
            throw MiddlewareError(description: "Missing Body")
        }
        let usesStreaming = try StudyChatResponsesRequestMetadata(body: input).usesStreaming
        let request = try await firebaseRequest(
            name: chatFunctionName,
            queryItems: [
                "ragEnabled": ragEnabled ? "true" : "false",
                "studyId": studyId
            ],
            body: input,
            acceptsStreaming: usesStreaming
        )
        guard usesStreaming else {
            let responseBody = try await callFirebaseFunction(request)
            return (
                HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
                HTTPBody(responseBody)
            )
        }
        let stream = makeResponseStream(for: request)
        let res = HTTPResponse(
            status: .ok,
            headerFields: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .connection: "keep-alive"
            ]
        )
        let body = HTTPBody(stream, length: .unknown)
        return (res, body)
    }

    private func firebaseRequest(
        name: String,
        queryItems: [String: String],
        body: String,
        acceptsStreaming: Bool
    ) async throws -> URLRequest {
        var components =
            URLComponents(string: name, encodingInvalidCharacters: false) ?? URLComponents()
        let nameItems = components.queryItems ?? []
        let nameKeys = Set(nameItems.map(\.name))
        let additionalItems =
            queryItems
            .filter { !nameKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = nameItems + additionalItems
        let queryString = components.percentEncodedQuery ?? ""
        let callableName = if queryString.isEmpty {
            name
        } else {
            "\(components.percentEncodedPath)?\(queryString)"
        }
        let functionURL = try self.functionURL(for: callableName)
        let idToken = try await auth.anonymouslySignIn()
        var urlRequest = URLRequest(url: functionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(acceptsStreaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: ["data": body])
        return urlRequest
    }

    private func functionURL(for name: String) throws -> URL {
        let urlString: String
        if let address = firebaseConfig.functionsEmulatorAddress {
            urlString = "http://\(address)/\(firebaseConfig.projectID)/\(firebaseConfig.region)/\(name)"
        } else {
            urlString = "https://\(firebaseConfig.region)-\(firebaseConfig.projectID).cloudfunctions.net/\(name)"
        }
        guard let url = URL(string: urlString) else {
            throw MiddlewareError(description: "Could not build function URL for '\(name)'")
        }
        return url
    }
    
    private func makeResponseStream(for urlRequest: URLRequest) -> AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error> {
        AsyncThrowingStream(HTTPBody.ByteChunk.self) { continuation in
            let task = Task { [urlRequest] in
                do {
                    let (bytes, httpResponse) = try await URLSession.shared.bytes(
                        for: urlRequest
                    )
                    guard let resp = httpResponse as? HTTPURLResponse,
                        resp.statusCode == 200
                    else {
                        print(
                            "Function call failed with status code: \((httpResponse as? HTTPURLResponse)?.statusCode ?? -1)"
                        )
                        throw MiddlewareError(description: "Function call failed")
                    }
                    var parser = FirebaseCallableStreamParser()
                    for try await line in bytes.lines {
                        if let chunk = try parser.consume(line) {
                            continuation.yield(HTTPBody.ByteChunk(chunk.utf8))
                        }
                        if parser.receivedTerminalResult {
                            break
                        }
                    }
                    try parser.finish()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func callFirebaseFunction(_ urlRequest: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw MiddlewareError(description: "Function call failed")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw MiddlewareError(description: "Function call returned an invalid response")
        }
        return result
    }
}

extension HTTPBody {
    fileprivate func data(upTo maxSize: Int) async throws -> some Collection<UInt8> {
        try await ArraySlice(collecting: self, upTo: maxSize)
    }
}
