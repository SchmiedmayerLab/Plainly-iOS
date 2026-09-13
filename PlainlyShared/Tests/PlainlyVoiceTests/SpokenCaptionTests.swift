//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import PlainlyVoice
import Testing


struct SpokenCaptionTests {
    @Test
    func showsOnlyWhatHasBeenHeard() {
        var caption = SpokenCaption()
        let line = UUID()

        #expect(caption.text(of: line, arrived: "Your MRI", queued: 1, played: 0).isEmpty)
        #expect(caption.text(of: line, arrived: "Your MRI shows", queued: 2, played: 1) == "Your MRI")
        #expect(caption.text(of: line, arrived: "Your MRI shows a bulge", queued: 3, played: 2.5) == "Your MRI shows")
        #expect(caption.text(of: line, arrived: "Your MRI shows a bulge", queued: 3, played: 3) == "Your MRI shows a bulge")
    }

    @Test
    func startsOverForANewLineOrAnEmptiedQueue() {
        var caption = SpokenCaption()
        _ = caption.text(of: UUID(), arrived: "Hello", queued: 5, played: 5)

        #expect(caption.text(of: UUID(), arrived: "Next", queued: 6, played: 5).isEmpty)

        let line = UUID()
        _ = caption.text(of: line, arrived: "A long answer", queued: 8, played: 2)
        #expect(caption.text(of: line, arrived: "A long answer goes on", queued: 0.5, played: 0.5) == "A long answer goes on")
    }

    @Test
    func interjectionsCarryTheirLimitsAndLanguage() {
        let configuration = VoiceConversation.Configuration(
            instructions: "Forward every turn.",
            toolName: "ask_plainly",
            language: Locale.Language(identifier: "de")
        )

        let spoken = configuration.interjection("Say hello.")

        #expect(spoken.hasPrefix(VoiceConversation.Configuration.interjectionGuard))
        #expect(spoken.hasSuffix("Say hello. Speak German, and only German."))
        #expect(configuration.unavailableAnswer.isEmpty == false)
    }

    @Test
    func keepsTheHeardSampleWhenTrimming() {
        var caption = SpokenCaption()
        let line = UUID()
        _ = caption.text(of: line, arrived: "Heard", queued: 1, played: 1)
        var shown = ""
        for index in 0..<700 {
            shown = caption.text(of: line, arrived: "Heard and more \(index)", queued: 2 + Double(index), played: 1)
        }

        #expect(shown == "Heard")
    }
}
