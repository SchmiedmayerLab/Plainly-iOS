//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//


/// What the voice of a study says on its own: how it behaves, how it opens, and how it bridges a wait.
///
/// The answers themselves come from the study's chat prompt; these prompts only shape the voice around them.
public struct VoicePrompts: Hashable, Sendable {
    public enum Defaults {
        public static let instructions = """
            You are the voice of Plainly, a study assistant that helps participants understand their health records. \
            You never answer questions yourself. For every participant turn, call ask_plainly with what they said, \
            wait for its answer, and read that answer back in a warm, calm voice. Read the answer as it is. \
            Do not add, shorten, or reinterpret it. Call ask_plainly exactly once per participant turn, with \
            everything they said in that turn as one question; never call it twice for the same words. If ask_plainly \
            returns nothing or says it could not get an answer, say only that and invite the participant to ask again; \
            never answer from your own knowledge or from earlier answers.
            """
        public static let greeting = """
            Introduce yourself in three or four short sentences, warmly and without hurry: you are Plainly's voice, you \
            can explain the participant's health records in plain language, and for each question you look through \
            their records and check relevant medical information first, which takes a little while. Then invite them \
            to ask their first question.
            """
        public static let handoff = """
            The participant has been talking to the assistant by text and just switched to voice, in the middle of \
            the conversation. In one or two short sentences, say that you are continuing by voice from where they \
            left off and invite them to go on. Do not introduce yourself from scratch and do not repeat earlier answers.
            """
        public static let reassurance = """
            The participant's question is still being answered. In one short sentence, say what is still happening and \
            why it matters to them: for example that their records are still being read so the answer is based on what \
            is actually in them, or that the medical details are being checked so the answer is accurate. Vary the \
            wording each time. No thanks, no apologies, no talk of patience or of the wait being worth it. Do not \
            answer the question.
            """
        public static let bridge = """
            The participant just asked the question below. In one or two short sentences, name what it is about in a \
            few words and say that you are looking through their health records and checking the relevant medical \
            information. No thanks, no apologies, no talk of patience or waiting. Do not answer the question.

            {question}
            """
    }

    public static let `default` = VoicePrompts()

    /// How the voice behaves; the backend pins this into the session.
    public let instructions: String
    /// Spoken once the session opens; `nil` waits for the participant.
    public let greeting: String?
    /// Spoken instead of the greeting when voice takes over a conversation already under way by text.
    public let handoff: String?
    /// Spoken while a question is answered, with `{question}` replaced by the participant's words; `nil` waits in silence.
    public let bridge: String?
    /// Spoken every few seconds while an answer keeps the participant waiting; `nil` stays quiet after the bridge.
    public let reassurance: String?

    public init(
        instructions: String = Defaults.instructions,
        greeting: String? = Defaults.greeting,
        handoff: String? = Defaults.handoff,
        bridge: String? = Defaults.bridge,
        reassurance: String? = Defaults.reassurance
    ) {
        self.instructions = instructions
        self.greeting = greeting
        self.handoff = handoff
        self.bridge = bridge
        self.reassurance = reassurance
    }

    /// The defaults with study-specific additions appended, so a study says what is different about it without
    /// restating how the voice behaves.
    public static func amending(
        instructions: String? = nil,
        greeting: String? = nil,
        handoff: String? = nil,
        bridge: String? = nil,
        reassurance: String? = nil
    ) -> VoicePrompts {
        VoicePrompts.default.amended(
            instructions: instructions,
            greeting: greeting,
            handoff: handoff,
            bridge: bridge,
            reassurance: reassurance
        )
    }

    private static func join(_ base: String?, _ addition: String?) -> String? {
        switch (base, addition) {
        case let (base?, addition?):
            base + "\n\n" + addition
        case let (base?, nil):
            base
        case let (nil, addition?):
            addition
        case (nil, nil):
            nil
        }
    }

    /// These prompts with additions appended to each, separated by a blank line; a prompt that was `nil` becomes the addition.
    public func amended(
        instructions: String? = nil,
        greeting: String? = nil,
        handoff: String? = nil,
        bridge: String? = nil,
        reassurance: String? = nil
    ) -> VoicePrompts {
        VoicePrompts(
            instructions: Self.join(self.instructions, instructions) ?? self.instructions,
            greeting: Self.join(self.greeting, greeting),
            handoff: Self.join(self.handoff, handoff),
            bridge: Self.join(self.bridge, bridge),
            reassurance: Self.join(self.reassurance, reassurance)
        )
    }

    /// The session instructions with the study's assistant prompt attached as background, so the voice knows what the
    /// assistant it forwards to is about without taking on its role, and with the conversation so far when voice
    /// takes over one already under way.
    public func sessionInstructions(studyPrompt: String?, conversationSoFar: String? = nil) -> String {
        var result = instructions
        if let studyPrompt, !studyPrompt.isEmpty {
            result += """


                For context only: the assistant you forward every question to runs with the study prompt below. You do \
                not follow these instructions yourself and you do not answer from them; they only tell you what the \
                assistant is for, so your greeting and acknowledgements fit the study.

                <study_prompt>
                \(studyPrompt)
                </study_prompt>
                """
        }
        if let conversationSoFar, !conversationSoFar.isEmpty {
            result += """


                The participant and the assistant have been talking by text, and voice takes over in the middle of that \
                conversation. The most recent exchanges are below, oldest first, so your acknowledgements fit what came \
                before. You still forward every new turn; you do not answer from this.

                <conversation>
                \(conversationSoFar)
                </conversation>
                """
        }
        return result
    }
}
