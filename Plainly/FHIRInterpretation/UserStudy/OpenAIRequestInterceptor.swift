//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import FirebaseFunctions
import Foundation
import HTTPTypes
import OpenAPIRuntime
import PlainlyShared
import Spezi


@Observable
final class OpenAIRequestInterceptor: Module, EnvironmentAccessible, ClientMiddleware, @unchecked Sendable {
    private struct Error: LocalizedError, CustomDebugStringConvertible {
        let description: String

        var errorDescription: String? {
            String(localized: "Plainly could not load chat content. Please try again.")
        }

        var debugDescription: String {
            description
        }

        init(_ description: String) {
            self.description = description
        }
    }
    
    @ObservationIgnored @Dependency(FHIRInterpretationModule.self) private var interpretationModule
    
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable @concurrent (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let maxBodySize = 7 * 1024 * 1024 // 7 MB
        let (endpoint, studyId) = await MainActor.run {
            let study = interpretationModule.currentStudy
            return (study?.config.openAIEndpoint ?? .regular, study?.study.id)
        }
        dispatchPrecondition(condition: .notOnQueue(.main))
        switch endpoint {
        case .regular:
            return try await next(request, body, baseURL)
        case .firebaseFunction(let name):
            guard let data = try await body?.data(upTo: maxBodySize),
                  let input = String(bytes: data, encoding: .utf8) else {
                throw Error("Missing Body")
            }
            let stream = streamFirebaseFunctionCall(
                name: name,
                queryItems: [
                    "ragEnabled": "true",
                    "studyId": studyId,
                    "mockChatError": FeatureFlags.useFirebaseMockChatError ? "true" : nil,
                    "mockChatErrorAfterChunk": FeatureFlags.useFirebaseMockChatErrorAfterChunk ? "true" : nil
                ].compactMapValues { $0 },
                body: input
            )
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
    }

    private func streamFirebaseFunctionCall(
        name: String,
        queryItems: [String: String],
        body: String,
    ) -> AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error> {
        let callableName = firebaseCallableName(name: name, queryItems: queryItems)
        let callable = Functions.functions()
            .httpsCallable(
                callableName,
                requestAs: String.self,
                responseAs: StreamResponse<String?, String?>.self
            )
        return AsyncThrowingStream(HTTPBody.ByteChunk.self) { continuation in
            let task = Task {
                do {
                    let stream = try callable.stream(body)
                    try await forwardFirebaseStream(stream, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func firebaseCallableName(name: String, queryItems: [String: String]) -> String {
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
        return if queryString.isEmpty {
            name
        } else {
            "\(components.percentEncodedPath)?\(queryString)"
        }
    }

    private func forwardFirebaseStream<Stream: AsyncSequence>(
        _ stream: Stream,
        continuation: AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error>.Continuation
    ) async throws where Stream.Element == StreamResponse<String?, String?> {
        var completionChunk: String?
        var receivedTerminalResult = false
        for try await event in stream {
            try Task.checkCancellation()
            let chunk = try responseChunk(from: event)
            switch event {
            case .message:
                guard let chunk else {
                    continue
                }
                let isDone = chunk.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]"
                if isDone {
                    completionChunk = chunk
                } else {
                    continuation.yield(HTTPBody.ByteChunk(chunk.utf8))
                }
            case .result:
                receivedTerminalResult = true
                if let completionChunk {
                    continuation.yield(HTTPBody.ByteChunk(completionChunk.utf8))
                }
            }
            if receivedTerminalResult {
                break
            }
        }
        guard receivedTerminalResult else {
            throw Error("Firebase chat function ended without a terminal result")
        }
    }

    private func responseChunk(from event: StreamResponse<String?, String?>) throws -> String? {
        switch event {
        case .message(let chunk):
            return chunk
        case .result(nil):
            return nil
        case .result(let result?):
            throw Error("Firebase chat function returned an unexpected result: \(result)")
        }
    }
}


extension HTTPBody {
    fileprivate func data(upTo maxSize: Int) async throws -> some Collection<UInt8> {
        try await ArraySlice(collecting: self, upTo: maxSize)
    }
}
