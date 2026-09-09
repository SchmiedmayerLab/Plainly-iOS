//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation
import GroveHealthKit
import GroveViews
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

    @Environment(PlainlyStandard.self) private var standard
    @Environment(HealthKit.self) private var healthKit: HealthKit?
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationStackPath
    @State private var authorizationState: AuthorizationState = .idle
    
    
    var body: some View {
        PageView {
            PageHeader(
                title: "HEALTHKIT_PERMISSIONS_TITLE",
                subtitle: "HEALTHKIT_PERMISSIONS_SUBTITLE",
                image: Image(systemName: "waveform.path.ecg.text.page.fill") // swiftlint:disable:this accessibility_label_for_image
            )
        } content: {
            Text("HEALTHKIT_PERMISSIONS_DESCRIPTION")
                .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            if authorizationState == .recoveryAvailable {
                PageActions(
                    primaryTitle: primaryButtonTitle,
                    primaryAction: requestAuthorization,
                    secondaryTitle: "HEALTHKIT_PERMISSIONS_SKIP_BUTTON",
                    secondaryAction: { completeAuthorization(fetchRecords: false) }
                )
                .actionButtonDisabled(.primary)
            } else {
                PageActions(primaryButtonTitle, viewState: primaryViewState, action: requestAuthorization)
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
            AppDiagnostics.healthRecords.warning(
                "Health Records permission flow has not returned after the recovery timeout"
            )
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

    /// The system sheet does the waiting, so the button only reflects it; nothing is written back.
    private var primaryViewState: Binding<ViewState> {
        Binding(get: { authorizationState.isProcessing ? .processing : .idle }, set: { _ in })
    }

    private func requestAuthorization() {
        guard authorizationState == .idle else {
            return
        }
        authorizationState = .requesting
        guard let healthKit else {
            AppDiagnostics.healthRecords.fault("HealthKit module is unavailable during permission request")
            completeAuthorization(fetchRecords: false)
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
                AppDiagnostics.healthRecords.logError(error, context: "Requesting Health Records permission")
                completeAuthorization(fetchRecords: false)
                return
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

    private func completeAuthorization(fetchRecords: Bool = true) {
        guard authorizationState != .completed else {
            return
        }
        authorizationState = .completed
        if fetchRecords {
            Task { await standard.fetchRecordsFromHealthKit() }
        }
        Task { @MainActor in
            await Task.yield()
            managedNavigationStackPath.nextStep()
        }
    }
}


#Preview {
    HealthKitPermissions()
}
