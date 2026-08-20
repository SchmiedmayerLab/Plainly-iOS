//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import GroveLLMOpenAI


// The models Plainly can request from the Firebase chat function.
//
// Every request is dispatched to the Firebase chat function, which resolves the provider and endpoint
// from the identifier alone. Models are therefore not limited to those served by OpenAI itself — the
// non-OpenAI entries are reachable through Stanford's AI API Gateway.
// swiftlint:disable identifier_name missing_docs
extension OpenAIPlatformDefinition.ModelType {
    /// The models a study is allowed to pin via ``PlainlyShared/Study/llmModel``.
    ///
    /// Enforced by `Study.validateAllStudies()`, which runs in the test suite and when the
    /// `export-config` tool generates a `UserStudyConfig.plist`.
    ///
    /// This remains an explicit allowlist even though Grove exposes additional model identifiers.
    public static let plainlySupportedModels: [Self] = [
        .gpt5_4, .gpt5_5,
        .gpt4o,
        .claudeOpus5, .claudeSonnet5, .claudeHaiku4_5,
        .gemini2_5Pro, .gemini2_5Flash, .gemini2_5FlashLite,
        .llama4
    ]

    // Anthropic
    public static let claudeOpus5 = Self(rawValue: "claude-opus-5")
    public static let claudeSonnet5 = Self(rawValue: "claude-sonnet-5")
    public static let claudeHaiku4_5 = Self(rawValue: "claude-haiku-4-5")

    // Google
    public static let gemini2_5Pro = Self(rawValue: "gemini-2.5-pro")
    public static let gemini2_5Flash = Self(rawValue: "gemini-2.5-flash")
    public static let gemini2_5FlashLite = Self(rawValue: "gemini-2.5-flash-lite")

    // Meta
    public static let llama4 = Self(rawValue: "Llama-4")
}
