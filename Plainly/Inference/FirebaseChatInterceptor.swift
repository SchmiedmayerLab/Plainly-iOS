//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import FirebaseFunctions
import Foundation
import Grove
import HTTPTypes
import OpenAPIRuntime
import PlainlyShared


/// Redirects the OpenAI client's Responses API requests to the Firebase chat function.
///
/// The app never holds inference credentials: the request body built by `GroveLLMOpenAI` is forwarded
/// verbatim to the function, which resolves the provider and endpoint from the model identifier.
@Observable
final class FirebaseChatInterceptor: Module, EnvironmentAccessible, ClientMiddleware, @unchecked Sendable {
    private typealias FirebaseChatCallable = Callable<String, StreamResponse<String?, String?>>
    private typealias FirebaseResponseCallable = Callable<String, String>

    /// The study-derived parameters forwarded to the Firebase chat function.
    private struct StudyDispatch {
        let functionName: String
        let studyID: String?
        let mayRetrieve: Bool
        /// Whether the study lets the model draw; the function refuses the tool otherwise.
        let generatesImages: Bool
    }

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
        let dispatch = await MainActor.run {
            let study = interpretationModule.currentStudy
            return StudyDispatch(
                functionName: study?.study.chatFunctionName ?? Study.defaultChatFunctionName,
                studyID: study?.study.id,
                // Retrieval serves the participant's questions, so it starts with their first message: the
                // generated opening turn, and whatever tool calls it makes, have nothing to retrieve for.
                mayRetrieve: (study?.study.ragEnabled ?? false) && interpretationModule.hasParticipantInput,
                generatesImages: study?.study.generatesImages ?? false
            )
        }
        dispatchPrecondition(condition: .notOnQueue(.main))
        return try await interceptFirebaseRequest(
            body: body,
            operationID: operationID,
            dispatch: dispatch,
            correlationID: correlationID
        )
    }
}


extension FirebaseChatInterceptor {
    private func interceptFirebaseRequest(
        body: HTTPBody?,
        operationID: String,
        dispatch: StudyDispatch,
        correlationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let input = try await firebaseRequestBody(body, operationID: operationID, correlationID: correlationID)
        let requestMetadata: StudyChatResponsesRequestMetadata
        do {
            requestMetadata = try StudyChatResponsesRequestMetadata(body: input)
        } catch {
            throw Error("Invalid Responses API request")
        }
        // Only the participant's own chat retrieves: the resource summarizer shares this transport and
        // advertises no health-record tool, so it must never pull study documents into its prompt.
        let shouldUseRAG = dispatch.mayRetrieve && requestMetadata.isStudyChatRequest
        let queryItems = [
            "ragEnabled": shouldUseRAG ? "true" : "false",
            "generatesImages": dispatch.generatesImages && requestMetadata.isStudyChatRequest ? "true" : "false",
            "studyId": dispatch.studyID,
            "mockScenario": FeatureFlags.firebaseMockScenario?.rawValue
        ].compactMapValues { $0 }
        guard requestMetadata.usesStreaming else {
            let responseBody = try await callFirebaseFunction(
                name: dispatch.functionName,
                queryItems: queryItems,
                body: input,
                correlationID: correlationID
            )
            return (
                HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
                HTTPBody(responseBody)
            )
        }
        let stream = streamFirebaseFunctionCall(
            name: dispatch.functionName,
            queryItems: queryItems,
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
                    body: body,
                    continuation: continuation,
                    correlationID: correlationID
                )
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func callFirebaseFunction(
        name: String,
        queryItems: [String: String],
        body: String,
        correlationID: String
    ) async throws -> String {
        let callable: FirebaseResponseCallable = Functions.functions()
            .httpsCallable(
                firebaseCallableName(name: name, queryItems: queryItems),
                requestAs: String.self,
                responseAs: String.self
            )
        do {
            return try await callable.call(body)
        } catch {
            AppDiagnostics.network.logError(error, context: "Firebase callable response", correlationID: correlationID)
            throw error
        }
    }

    private func runFirebaseStream(
        _ callable: FirebaseChatCallable,
        body: String,
        continuation: AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error>.Continuation,
        correlationID: String
    ) async {
        do {
            let stream = try callable.stream(body)
            try await forwardFirebaseStream(stream, continuation: continuation, correlationID: correlationID)
            continuation.finish()
        } catch is CancellationError {
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
                forwardedChunkCount += 1
                forwardedByteCount += chunk.utf8.count
                continuation.yield(HTTPBody.ByteChunk(chunk.utf8))
            case .result:
                receivedTerminalResult = true
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
