//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import PlainlyShared


extension Study {
    /// All studies participants can take part in.
    public static var allStudies: [Study] {
        [.usabilityStudy, .gynStudy, .spineAI, .languageStudy, .pedCardioStudy]
    }

    /// Studies that only exist to try something out, which development builds offer next to ``allStudies``.
    public static var previewStudies: [Study] {
        [.voiceDemo]
    }
}

extension Study {
    /// Fetches the study with the specified id, if available.
    public static func withId(_ id: Study.ID) -> Study? {
        allStudies.first { $0.id == id }
    }
}
