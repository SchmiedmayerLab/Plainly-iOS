//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziOnboarding
import SpeziViews
import SwiftUI


private struct DisclaimerItem: View {
    let title: LocalizedStringResource
    let description: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .bold()
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct Disclaimer: View {
    @Environment(ManagedNavigationStack.Path.self) private var path

    var body: some View {
        OnboardingView {
            VStack(alignment: .leading, spacing: 6) {
                Text("DISCLAIMER_TITLE")
                    .font(.title)
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Text("DISCLAIMER_SUBTITLE")
                    .font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                DisclaimerItem(
                    title: "DISCLAIMER_AREA1_TITLE",
                    description: "DISCLAIMER_AREA1_DESCRIPTION"
                )
                DisclaimerItem(
                    title: "DISCLAIMER_AREA2_TITLE",
                    description: "DISCLAIMER_AREA2_DESCRIPTION"
                )
                DisclaimerItem(
                    title: "DISCLAIMER_AREA3_TITLE",
                    description: "DISCLAIMER_AREA3_DESCRIPTION"
                )
                DisclaimerItem(
                    title: "DISCLAIMER_AREA4_TITLE",
                    description: "DISCLAIMER_AREA4_DESCRIPTION"
                )
            }
        } footer: {
            OnboardingActionsView("DISCLAIMER_BUTTON") {
                path.nextStep()
            }
        }
        .font(.subheadline)
    }
}


#Preview {
    Disclaimer()
}
