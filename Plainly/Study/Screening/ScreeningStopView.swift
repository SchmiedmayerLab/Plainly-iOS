//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import PlainlyShared
import SwiftUI


/// The page a participant sees once screening has stopped the study.
///
/// Symptoms that need attention put medical help first: the page offers emergency services and nearby
/// emergency care before it mentions the study at all. An ineligible outcome sends the participant to the study
/// coordinator. Both replace the study home for good, so there is no way into the chat from here.
struct ScreeningStopView: View {
    private static let emergencyNumber = URL(string: "tel:911")!
    private static let emergencyCare = URL(string: "https://maps.apple.com/?q=emergency%20room")!

    private let outcome: ScreeningOutcome

    @Environment(\.openURL) private var openURL

    var body: some View {
        PageView {
            PageHeader(title: title, image: Image(systemName: symbol)) // swiftlint:disable:this accessibility_label_for_image
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                Text("SCREENING_COORDINATOR_NEXT")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ScreeningStopMessage")
        } footer: {
            if outcome == .needsAttention {
                PageActions(
                    primaryTitle: "SCREENING_CALL_EMERGENCY_SERVICES",
                    primaryAction: { openURL(Self.emergencyNumber) },
                    secondaryTitle: "SCREENING_FIND_EMERGENCY_CARE",
                    secondaryAction: { openURL(Self.emergencyCare) }
                )
            }
        }
    }

    private var title: LocalizedStringResource {
        switch outcome {
        case .needsAttention: "SCREENING_ATTENTION_TITLE"
        case .ineligible: "SCREENING_INELIGIBLE_TITLE"
        case .eligible: "SCREENING_ELIGIBLE_TITLE"
        }
    }

    private var message: LocalizedStringResource {
        switch outcome {
        case .needsAttention: "SCREENING_ATTENTION_MESSAGE"
        case .ineligible: "SCREENING_INELIGIBLE_MESSAGE"
        case .eligible: "SCREENING_ELIGIBLE_MESSAGE"
        }
    }

    private var symbol: String {
        switch outcome {
        case .needsAttention: "stethoscope"
        case .ineligible: "person.crop.circle.badge.xmark"
        case .eligible: "checkmark.seal.fill"
        }
    }

    init(outcome: ScreeningOutcome) {
        self.outcome = outcome
    }
}


#if DEBUG
#Preview("Needs Attention") {
    ScreeningStopView(outcome: .needsAttention)
}

#Preview("Ineligible") {
    ScreeningStopView(outcome: .ineligible)
}
#endif
