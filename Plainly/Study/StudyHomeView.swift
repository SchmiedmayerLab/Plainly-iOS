//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveFHIRMockPatients
import GroveFoundation
import GroveHealthKit
import struct ModelsR4.QuestionnaireResponse
import PlainlyShared
import SwiftUI


struct StudyHomeView: View {
    private let preloadedStudy: InProgressStudy?
    
    @LocalPreference(.resourceLimit) private var resourceLimit
    @Environment(PlainlyStandard.self) private var standard
    @Environment(HealthKit.self) private var healthKit
    @Environment(FHIRInterpretationModule.self) private var fhirInterpretationModule
    @Environment(FirebaseUpload.self) private var uploader: FirebaseUpload?
    @Environment(PendingReportStore.self) private var pendingReports: PendingReportStore?
    @WaitingState private var waitingState
    
    @State private var isPresentingQuestionnaire = false
    // A UI test can open the chat without answering a study's questionnaire first.
    @State private var questionnaireResponse: QuestionnaireResponse? = FeatureFlags.skipInitialQuestionnaire
        ? QuestionnaireResponse(status: .init(.completed))
        : nil
    
    @State private var isPresentingEarliestHealthRecords = false
    @State private var isPresentingQRCodeScanner = false
    
    @State private var isPresentingStudyChatView = false
    
    var body: some View {
        NavigationStack {
            studyContent
        }
    }

    private var studyContent: some View {
        observedContent
    }

    private var navigationContent: some View {
        mainContent
            .background(Color(.systemBackground))
            .navigationTitle("USER_STUDY_WECOME")
            .navigationBarTitleDisplayMode(.inline)
            #if targetEnvironment(simulator)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsButton()
                }
            }
            #endif
    }

    private var presentationContent: some View {
        navigationContent
            .sheet(isPresented: $isPresentingEarliestHealthRecords) {
                EarliestHealthRecordsView(dataSource: earliestDates)
                    .presentationDetents([.medium, .large])
            }
            .qrCodeScanningSheet(isPresented: $isPresentingQRCodeScanner) { payload in
                processStudyQRCode(payload)
            }
            .fullScreenCover(isPresented: $isPresentingQuestionnaire) {
                questionnaireSheetContent
            }
            .fullScreenCover(isPresented: $isPresentingStudyChatView) {
                chatSheetContent
            }
            .onChange(of: isPresentingStudyChatView) { _, isPresenting in
                guard !isPresenting else {
                    return
                }
                pendingReports?.retryPendingUploads()
            }
    }

    private var observedContent: some View {
        presentationContent
            .task {
                await prepareInitialStudyState()
            }
            .task(id: fhirInterpretationModule.currentStudy?.study.id) {
                await preloadInitialQuestionnaire()
            }
    }

    @ViewBuilder private var questionnaireSheetContent: some View {
        if let currentStudy = fhirInterpretationModule.currentStudy {
            IntakeQuestionnaireSheet(
                inProgressStudy: currentStudy,
                response: $questionnaireResponse
            )
        } else {
            ContentUnavailableView("Study not selected", systemImage: "document.badge.gearshape")
                .onAppear {
                    AppDiagnostics.questionnaire.fault(
                        "Questionnaire presentation requested without a selected study"
                    )
                }
        }
    }

    @ViewBuilder private var chatSheetContent: some View {
        if let currentStudy = fhirInterpretationModule.currentStudy {
            StudyChatView(model: .init(
                inProgressStudy: currentStudy,
                initialQuestionnaireResponse: questionnaireResponse,
                interpretationModule: fhirInterpretationModule,
                uploader: uploader,
                pendingReports: pendingReports
            ))
        } else {
            ContentUnavailableView("Study not selected", systemImage: "document.badge.gearshape")
                .onAppear {
                    AppDiagnostics.chat.fault(
                        "Chat presentation requested without a selected study"
                    )
                }
        }
    }


    private var mainContent: some View {
        VStack {
            Spacer()
            studyLogo
            studyInformation
            Spacer()
            bottomSection
        }
    }

    private var studyLogo: some View {
        Image("StanfordBlockSTree")
            .resizable()
            .scaledToFill()
            .frame(width: 100, height: 100)
            .accessibilityLabel(Text("Stanford Logo"))
    }

    private var studyInformation: some View {
        VStack(spacing: 24) {
            studyTitle
            studyDescription
        }
        .padding(.top, 48)
    }

    private var studyTitle: some View {
        VStack(spacing: 8) {
            Text(fhirInterpretationModule.currentStudy?.study.title ?? "Plainly")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
    }

    private var studyDescription: some View {
        let text: LocalizedStringResource = (fhirInterpretationModule.currentStudy?.study.explainer)
            .map { "\($0)" } ?? "Scan a QR Code to Participate in a Study"
        return Text(text)
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32)
    }

    @ViewBuilder private var recordsStartDateView: some View {
        if let oldestHealthRecordTimestamp {
            Button {
                isPresentingEarliestHealthRecords = true
            } label: {
                Text("HEALTH_RECORDS_SINCE: \(oldestHealthRecordTimestamp, format: .plainlyOldestHealthSample)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                    .underline()
            }
            .opacity(waitingState.isWaiting ? 0 : 1)
            .padding(.bottom, 16)
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 16) {
            pendingReportsView
                .padding(.horizontal, 32)
            primaryActionButton
                .padding(.horizontal, 32)
                .transforming { view in
                    if #available(iOS 26, *) {
                        view.buttonStyle(.glassProminent)
                    } else {
                        view
                            .background(Color.accent.opacity(waitingState.isWaiting ? 0.5 : 1))
                            .cornerRadius(16)
                            .buttonStyle(.borderedProminent)
                    }
                }
            recordsStartDateView
        }
        .padding(.bottom, 24)
    }
    
    @ViewBuilder private var pendingReportsView: some View {
        if let pendingReports, pendingReports.pendingCount > 0 {
            PendingReportsView(count: pendingReports.pendingCount, isUploading: pendingReports.isUploading) {
                pendingReports.retryPendingUploads()
            }
        }
    }

    private var primaryActionButton: some View {
        PrimaryActionButton {
            if fhirInterpretationModule.currentStudy != nil {
                if isMissingPreChatQuestionnaire {
                    isPresentingQuestionnaire = true
                    return
                }
                // the HealthKit permissions should already have been granted via the onboarding, but we re-request them here, just in case,
                // to make sure everything is in a proper state when the study gets launched.
                do {
                    try await healthKit.askForAuthorization()
                } catch {
                    AppDiagnostics.healthRecords.logError(
                        error,
                        context: "Refreshing Health Records authorization before chat"
                    )
                    throw error
                }
                await fhirInterpretationModule.updateSchemas()
                isPresentingStudyChatView = true
            } else {
                isPresentingQRCodeScanner = true
            }
        } label: {
            if waitingState.isWaiting {
                Text("LOADING_HEALTH_RECORDS")
            } else if fhirInterpretationModule.currentStudy != nil {
                if isMissingPreChatQuestionnaire {
                    Text("Start Questionnaire")
                } else {
                    Text("START_SESSION")
                }
            } else {
                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
            }
        }
    }
}


extension StudyHomeView {
    private var earliestDates: [String: Date] {
        fhirInterpretationModule.multipleResourceInterpreter.fhirStore.earliestDates(limit: resourceLimit)
    }

    private var oldestHealthRecordTimestamp: Date? {
        earliestDates.values.min()
    }

    /// Whether the currently enabled study has an initial questionnaire, and the user still needs to fill that out.
    private var isMissingPreChatQuestionnaire: Bool {
        fhirInterpretationModule.currentStudy?.study.hasInitialQuestionnaire == true && questionnaireResponse == nil
    }

    init(study: Study, userInfo: [String: String]) {
        preloadedStudy = InProgressStudy(study: study, userInfo: userInfo)
    }
    
    init() {
        preloadedStudy = nil
    }

    @MainActor
    private func processStudyQRCode(_ payload: String) -> QRCodeScanningResponse {
        guard fhirInterpretationModule.currentStudy == nil else {
            return .stopScanning
        }
        do {
            let scanResult = try StudyQRCodeHandler.processQRCode(payload: payload)
            isPresentingQRCodeScanner = false
            fhirInterpretationModule.currentStudy = .init(study: scanResult.study, userInfo: scanResult.userInfo)
            return .stopScanning
        } catch {
            AppDiagnostics.study.logError(error, context: "Selecting study from QR code")
            return .continueScanning
        }
    }

    @MainActor
    private func prepareInitialStudyState() async {
        if let preloadedStudy {
            fhirInterpretationModule.currentStudy = preloadedStudy
        }
        if FeatureFlags.usesSampleHealthRecords {
            await fhirInterpretationModule.multipleResourceInterpreter.fhirStore.loadTestingResources()
        } else {
            await standard.fetchRecordsFromHealthKit()
        }
        await fhirInterpretationModule.updateSchemas()
    }

    private func preloadInitialQuestionnaire() async {
        guard let study = fhirInterpretationModule.currentStudy?.study else {
            return
        }
        do {
            guard let url = try study.initialQuestionnaireURL(in: .main) else {
                return
            }
            _ = try await QuestionnaireLoader.shared.questionnaire(from: url)
        } catch is CancellationError {
            return
        } catch {
            AppDiagnostics.questionnaire.logError(error, context: "Questionnaire preload")
        }
    }
}
