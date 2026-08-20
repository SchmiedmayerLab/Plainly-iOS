//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveLLM


/// Input Plainly supplies on its own behalf.
///
/// A Responses API request needs something to answer, and the instructions that frame it are not that. Where
/// the previous transport accepted a prompt by itself, Plainly now has to say what the prompt is about — so
/// these are the turns it writes rather than the participant.
public enum InternalInput {
    /// Identifies the study chat's opening input, which is kept out of what the participant reads and out
    /// of the study report.
    public static let conversationStarterID = UUID(uuidString: "28B1807E-8888-43D1-963D-340330E66855") ?? UUID()
    /// Opens a study conversation, leaving the study's own instructions to decide what it opens with.
    public static let conversationStarter = "Follow the study instructions to begin the conversation."
    /// Asks for the one summary the surrounding instructions describe.
    public static let resourceSummaryRequest = "Produce the requested resource summary now."
}


extension LLMContextEntity {
    /// Whether the participant wrote this turn, rather than Plainly writing one on their behalf.
    public var isParticipantInput: Bool {
        role == .user && id != InternalInput.conversationStarterID
    }
}
