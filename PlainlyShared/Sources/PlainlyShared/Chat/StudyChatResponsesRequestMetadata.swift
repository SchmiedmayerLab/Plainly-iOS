//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A malformed body cannot be routed as a Responses API request.
public enum StudyChatResponsesRequestMetadataError: Error {
    /// The body is not a JSON object encoded as UTF-8.
    case invalidBody
}


/// Information Plainly needs to route a Grove Responses API request through Firebase.
public struct StudyChatResponsesRequestMetadata: Sendable {
    /// Whether the client expects a server-sent event stream.
    public let usesStreaming: Bool
    /// Whether the request belongs to the participant's own chat.
    ///
    /// Told apart by the health-record tool: everything else sharing this transport — summarizing a single
    /// resource, describing an annotated image — asks the model to work on what it was given.
    public let isStudyChatRequest: Bool

    /// Parses metadata from a Responses API request body.
    public init(body: String) throws {
        // Every malformed body arrives as the one error this type declares, rather than as whatever
        // `JSONSerialization` happened to raise.
        guard let data = body.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw StudyChatResponsesRequestMetadataError.invalidBody
        }
        let tools = json["tools"] as? [[String: Any]] ?? []
        isStudyChatRequest = tools.contains {
            ($0["type"] as? String) == "function" && ($0["name"] as? String) == FHIRGetResourceLLMTool.toolName
        }
        usesStreaming = json["stream"] as? Bool ?? false
    }
}
