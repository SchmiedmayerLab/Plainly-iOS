//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import OSLog
import SpeziFoundation
import SpeziHealthKit
import SpeziOnboarding
import SpeziViews
import SwiftUI


struct HealthKitPermissions: View {
    private enum AuthorizationState: Equatable {
        case idle
        case requesting
        case recoveryAvailable
        case completed

        var isProcessing: Bool {
            self == .requesting || self == .recoveryAvailable
        }
    }

    private let logger = Logger(subsystem: "edu.stanford.plainly", category: "HealthKitPermissions")

    @Environment(PlainlyStandard.self) private var standard
    @Environment(HealthKit.self) private var healthKit: HealthKit?
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationStackPath
    @State private var authorizationState: AuthorizationState = .idle
    
    
    var body: some View {
        OnboardingView {
            VStack {
                OnboardingTitleView(
                    title: "HEALTHKIT_PERMISSIONS_TITLE",
                    subtitle: "HEALTHKIT_PERMISSIONS_SUBTITLE"
                )
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .accessibilityHidden(true)
                    .font(.system(size: 150))
                    .foregroundColor(.accentColor)
                Text("HEALTHKIT_PERMISSIONS_DESCRIPTION")
                    .multilineTextAlignment(.leading)
                    .padding(.vertical, 16)
                Spacer()
            }
        } footer: {
            VStack(spacing: 0) {
                Button(action: requestAuthorization) {
                    HStack {
                        Text(primaryButtonTitle)
                            .bold()
                        if authorizationState.isProcessing {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(authorizationState != .idle)

                if authorizationState == .recoveryAvailable {
                    Button("HEALTHKIT_PERMISSIONS_SKIP_BUTTON", action: completeAuthorization)
                        .padding(.vertical, 10)
                }
            }
        }
        .navigationBarBackButtonHidden(authorizationState.isProcessing)
        .task(id: authorizationState) {
            guard authorizationState == .requesting else {
                return
            }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, authorizationState == .requesting else {
                return
            }
            authorizationState = .recoveryAvailable
        }
        .onChange(of: healthKit?.isFullyAuthorized) { _, isFullyAuthorized in
            if isFullyAuthorized == true {
                completeAuthorization()
            }
        }
    }

    private var primaryButtonTitle: LocalizedStringResource {
        authorizationState.isProcessing ? "HEALTHKIT_PERMISSIONS_WAITING" : "HEALTHKIT_PERMISSIONS_BUTTON"
    }

    private func requestAuthorization() {
        guard authorizationState == .idle else {
            return
        }
        authorizationState = .requesting
        guard let healthKit else {
            completeAuthorization()
            return
        }

        Task { @MainActor in
            await monitorAuthorizationDecision(using: healthKit)
        }
        Task { @MainActor in
            if await healthKit.didAskForAuthorization(toRead: PlainlyStandard.recordTypes) {
                completeAuthorization()
                return
            }
            do {
                // HealthKit is not available in the preview simulator.
                if ProcessInfo.processInfo.isPreviewSimulator {
                    try await Task.sleep(for: .seconds(5))
                } else {
                    try await healthKit.askForAuthorization()
                }
            } catch {
                logger.error("Could not request HealthKit permissions: \(error)")
            }
            completeAuthorization()
        }
    }

    private func monitorAuthorizationDecision(using healthKit: HealthKit) async {
        while authorizationState.isProcessing {
            if await healthKit.didAskForAuthorization(toRead: PlainlyStandard.recordTypes) {
                completeAuthorization()
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func completeAuthorization() {
        guard authorizationState != .completed else {
            return
        }
        authorizationState = .completed
        Task { await standard.fetchRecordsFromHealthKit() }
        Task { @MainActor in
            await Task.yield()
            managedNavigationStackPath.nextStep()
        }
    }
}


#Preview {
    HealthKitPermissions()
}
