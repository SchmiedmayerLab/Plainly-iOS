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
    private typealias FirebaseChatCallable = Callable<String, StreamResponse<String?, String?>>

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
        let correlationID = AppDiagnostics.correlationID()
        let (endpoint, studyId) = await MainActor.run {
            let study = interpretationModule.currentStudy
            return (study?.config.openAIEndpoint ?? .regular, study?.study.id)
        }
        dispatchPrecondition(condition: .notOnQueue(.main))
        switch endpoint {
        case .regular:
            AppDiagnostics.network.notice("""
                Passing direct inference request to the HTTP client; correlation=\(correlationID, privacy: .public); \
                operation=\(operationID, privacy: .public); hasBody=\(body != nil)
                """)
            return try await interceptDirectRequest(
                request,
                body: body,
                baseURL: baseURL,
                correlationID: correlationID,
                next: next
            )
        case .firebaseFunction(let name):
            return try await interceptFirebaseRequest(
                body: body,
                operationID: operationID,
                functionName: name,
                studyID: studyId,
                correlationID: correlationID
            )
        }
    }
}


extension OpenAIRequestInterceptor {
    private func interceptDirectRequest(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        correlationID: String,
        next: @Sendable @concurrent (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        do {
            let response = try await next(request, body, baseURL)
            AppDiagnostics.network.notice(
                "Direct inference HTTP request returned; correlation=\(correlationID, privacy: .public); status=\(response.0.status.code)"
            )
            return response
        } catch {
            AppDiagnostics.network.logError(error, context: "Direct inference HTTP request", correlationID: correlationID)
            throw error
        }
    }

    private func interceptFirebaseRequest(
        body: HTTPBody?,
        operationID: String,
        functionName: String,
        studyID: String?,
        correlationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let input = try await firebaseRequestBody(body, operationID: operationID, correlationID: correlationID)
        AppDiagnostics.network.notice("""
            Routing inference request through Firebase; correlation=\(correlationID, privacy: .public); \
            operation=\(operationID, privacy: .public); function=\(functionName, privacy: .public); \
            bodyBytes=\(input.utf8.count); hasStudyID=\(studyID != nil)
            """)
        let stream = streamFirebaseFunctionCall(
            name: functionName,
            queryItems: [
                "ragEnabled": "true",
                "studyId": studyID,
                "mockChatError": FeatureFlags.useFirebaseMockChatError ? "true" : nil,
                "mockChatErrorAfterChunk": FeatureFlags.useFirebaseMockChatErrorAfterChunk ? "true" : nil
            ].compactMapValues { $0 },
            body: input,
            correlationID: correlationID
        )
        let response = HTTPResponse(
            status: .ok,
            headerFields: [.contentType: "text/event-stream", .cacheControl: "no-cache", .connection: "keep-alive"]
        )
        return (response, HTTPBody(stream, length: .unknown))
    }

    private func firebaseRequestBody(
        _ body: HTTPBody?,
        operationID: String,
        correlationID: String
    ) async throws -> String {
        guard let body else {
            AppDiagnostics.network.fault("""
                Firebase inference request body is missing; correlation=\(correlationID, privacy: .public); \
                operation=\(operationID, privacy: .public)
                """)
            throw Error("Missing Body")
        }
        let data: ArraySlice<UInt8>
        do {
            data = try await body.data(upTo: 7 * 1024 * 1024)
        } catch {
            AppDiagnostics.network.logError(error, context: "Reading Firebase inference request body", correlationID: correlationID)
            throw error
        }
        guard let input = String(bytes: data, encoding: .utf8) else {
            AppDiagnostics.network.fault("""
                Firebase inference request body is not UTF-8; correlation=\(correlationID, privacy: .public); \
                operation=\(operationID, privacy: .public); bodyBytes=\(data.count)
                """)
            throw Error("Invalid Body Encoding")
        }
        return input
    }

    private func streamFirebaseFunctionCall(
        name: String,
        queryItems: [String: String],
        body: String,
        correlationID: String
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
                await runFirebaseStream(
                    callable,
                    functionName: name,
                    body: body,
                    continuation: continuation,
                    correlationID: correlationID
                )
            }
            continuation.onTermination = { @Sendable termination in
                let reason: StaticString
                let hasError: Bool
                switch termination {
                case .cancelled:
                    reason = "cancelled"
                    hasError = false
                case .finished(let error):
                    reason = "finished"
                    hasError = error != nil
                @unknown default:
                    reason = "unknown"
                    hasError = false
                }
                AppDiagnostics.network.notice("""
                    Firebase response body consumer terminated; correlation=\(correlationID, privacy: .public); \
                    reason=\(reason, privacy: .public); hasError=\(hasError)
                    """)
                task.cancel()
            }
        }
    }

    private func runFirebaseStream(
        _ callable: FirebaseChatCallable,
        functionName: String,
        body: String,
        continuation: AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error>.Continuation,
        correlationID: String
    ) async {
        let signpostID = AppDiagnostics.networkSignposter.makeSignpostID()
        let interval = AppDiagnostics.networkSignposter.beginInterval(
            "FirebaseChatStream",
            id: signpostID,
            "correlation=\(correlationID, privacy: .public)"
        )
        defer {
            AppDiagnostics.networkSignposter.endInterval("FirebaseChatStream", interval)
        }
        do {
            AppDiagnostics.network.notice("""
                Firebase callable stream starting; correlation=\(correlationID, privacy: .public); \
                function=\(functionName, privacy: .public)
                """)
            let stream = try callable.stream(body)
            try await forwardFirebaseStream(stream, continuation: continuation, correlationID: correlationID)
            AppDiagnostics.network.notice(
                "Firebase callable stream completed; correlation=\(correlationID, privacy: .public)"
            )
            continuation.finish()
        } catch is CancellationError {
            AppDiagnostics.network.notice(
                "Firebase callable stream cancelled; correlation=\(correlationID, privacy: .public)"
            )
            continuation.finish()
        } catch {
            AppDiagnostics.network.logError(error, context: "Firebase callable stream", correlationID: correlationID)
            continuation.finish(throwing: error)
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
        continuation: AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error>.Continuation,
        correlationID: String
    ) async throws where Stream.Element == StreamResponse<String?, String?> {
        var completionChunk: String?
        var forwardedChunkCount = 0
        var forwardedByteCount = 0
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
                    AppDiagnostics.network.info(
                        "Firebase completion marker received; correlation=\(correlationID, privacy: .public)"
                    )
                } else {
                    if forwardedChunkCount == 0 {
                        AppDiagnostics.network.notice(
                            "Firebase first response chunk received; correlation=\(correlationID, privacy: .public)"
                        )
                    }
                    forwardedChunkCount += 1
                    forwardedByteCount += chunk.utf8.count
                    continuation.yield(HTTPBody.ByteChunk(chunk.utf8))
                }
            case .result:
                receivedTerminalResult = true
                AppDiagnostics.network.notice("""
                    Firebase terminal result received; correlation=\(correlationID, privacy: .public); \
                    forwardedChunks=\(forwardedChunkCount); forwardedBytes=\(forwardedByteCount); \
                    hasCompletionMarker=\(completionChunk != nil)
                    """)
                if let completionChunk {
                    continuation.yield(HTTPBody.ByteChunk(completionChunk.utf8))
                }
            }
            if receivedTerminalResult {
                break
            }
        }
        guard receivedTerminalResult else {
            AppDiagnostics.network.fault("""
                Firebase stream ended without a terminal result; correlation=\(correlationID, privacy: .public); \
                forwardedChunks=\(forwardedChunkCount); forwardedBytes=\(forwardedByteCount)
                """)
            throw Error("Firebase chat function ended without a terminal result")
        }
    }

    private func responseChunk(from event: StreamResponse<String?, String?>) throws -> String? {
        switch event {
        case .message(let chunk):
            return chunk
        case .result(nil):
            return nil
        case .result(.some):
            throw Error("Firebase chat function returned an unexpected nonempty result")
        }
    }
}


extension HTTPBody {
    fileprivate func data(upTo maxSize: Int) async throws -> ArraySlice<UInt8> {
        try await ArraySlice(collecting: self, upTo: maxSize)
    }
}
