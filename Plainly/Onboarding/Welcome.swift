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


struct Welcome: View {
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationStackPath
    
    var body: some View {
        PageView(
            title: "WELCOME_TITLE",
            subtitle: "WELCOME_SUBTITLE",
            areas: [
                OnboardingInformationView.Area(
                    iconSymbol: "waveform.path.ecg.text.page.fill",
                    title: "WELCOME_AREA1_TITLE",
                    description: "WELCOME_AREA1_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    iconSymbol: "wand.and.sparkles",
                    title: "WELCOME_AREA2_TITLE",
                    description: "WELCOME_AREA2_DESCRIPTION"
                ),
                OnboardingInformationView.Area(
                    iconSymbol: "text.bubble.fill",
                    title: "WELCOME_AREA3_TITLE",
                    description: "WELCOME_AREA3_DESCRIPTION"
                )
            ],
            actionText: "WELCOME_BUTTON",
            action: {
                managedNavigationStackPath.nextStep()
            }
        )
        .toolbar {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                ToolbarItem(placement: .topBarLeading) {
                    CreateQRCodeButton()
                }
            }
        }
    }
}


#Preview {
    Welcome()
}
