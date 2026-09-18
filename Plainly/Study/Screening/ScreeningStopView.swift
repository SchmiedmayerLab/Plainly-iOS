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
/// Symptoms that need attention put medical help first: the page offers the study's urgent care, or emergency
/// services where it names none, and nearby emergency care before it mentions the study at all. An ineligible
/// outcome sends the participant to the study coordinator. Both replace the study home for good, so there is no way
/// into the chat from here.
struct ScreeningStopView: View {
    private static let emergencyNumber = URL(string: "tel:911")!
    private static let emergencyCare = URL(string: "https://maps.apple.com/?q=emergency%20room")!

    private let outcome: ScreeningOutcome
    private let urgentCare: Study.UrgentCare?

    @Environment(\.openURL) private var openURL

    var body: some View {
        PageView {
            PageHeader(title: title, image: Image(systemName: symbol)) // swiftlint:disable:this accessibility_label_for_image
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                Text(urgentCare == nil ? "SCREENING_COORDINATOR_NEXT" : "SCREENING_COORDINATOR_FOLLOW_UP")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("ScreeningStopMessage")
        } footer: {
            if outcome == .needsAttention {
                PageActions(
                    primaryTitle: urgentCare.map { "SCREENING_CALL_URGENT_CARE \($0.name)" } ?? "SCREENING_CALL_EMERGENCY_SERVICES",
                    primaryAction: { openURL(urgentCare?.phoneURL ?? Self.emergencyNumber) },
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
        switch (outcome, urgentCare) {
        case let (.needsAttention, urgentCare?): "SCREENING_ATTENTION_URGENT_CARE_MESSAGE \(urgentCare.name) \(urgentCare.phoneNumber)"
        case (.needsAttention, nil): "SCREENING_ATTENTION_MESSAGE"
        case (.ineligible, _): "SCREENING_INELIGIBLE_MESSAGE"
        case (.eligible, _): "SCREENING_ELIGIBLE_MESSAGE"
        }
    }

    private var symbol: String {
        switch outcome {
        case .needsAttention: "stethoscope"
        case .ineligible: "person.crop.circle.badge.xmark"
        case .eligible: "checkmark.seal.fill"
        }
    }

    init(outcome: ScreeningOutcome, urgentCare: Study.UrgentCare? = nil) {
        self.outcome = outcome
        self.urgentCare = urgentCare
    }
}


#if DEBUG
#Preview("Needs Attention") {
    ScreeningStopView(outcome: .needsAttention)
}

#Preview("Needs Urgent Care") {
    ScreeningStopView(outcome: .needsAttention, urgentCare: .init(name: "Spine Center", phoneNumber: "(650) 725-5905"))
}

#Preview("Ineligible") {
    ScreeningStopView(outcome: .ineligible)
}
#endif
