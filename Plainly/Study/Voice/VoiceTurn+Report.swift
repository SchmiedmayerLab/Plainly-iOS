//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import PlainlyShared
import PlainlyVoice


extension VoiceTurn {
    var studyReportEvent: StudyReport.TimelineEvent {
        .voiceTurn(.init(
            startedAt: startedAt,
            transcript: transcript,
            transcriptSource: transcriptSource.rawValue,
            toolCall: .init(name: toolName, arguments: arguments),
            answer: answer,
            spokenTranscript: spokenTranscript
        ))
    }
}
