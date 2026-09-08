//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveOnboarding
import GroveViews
import SwiftUI


struct Disclaimer: View {
    @Environment(ManagedNavigationStack.Path.self) private var path

    var body: some View {
        PageView(
            title: "DISCLAIMER_TITLE",
            subtitle: "DISCLAIMER_SUBTITLE",
            areas: [
                OnboardingInformationView.Area(
                    iconSymbol: "info.circle.fill",
                    title: "DISCLAIMER_AREA1_TITLE",
                    description: "DISCLAIMER_AREA1_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    iconSymbol: "exclamationmark.triangle.fill",
                    title: "DISCLAIMER_AREA2_TITLE",
                    description: "DISCLAIMER_AREA2_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    iconSymbol: "stethoscope.circle.fill",
                    title: "DISCLAIMER_AREA3_TITLE",
                    description: "DISCLAIMER_AREA3_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    iconSymbol: "flask.fill",
                    title: "DISCLAIMER_AREA4_TITLE",
                    description: "DISCLAIMER_AREA4_DESCRIPTION"
                )
            ],
            actionText: "DISCLAIMER_BUTTON",
            action: {
                path.nextStep()
            }
        )
    }
}


#Preview {
    Disclaimer()
}
