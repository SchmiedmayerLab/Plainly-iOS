//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import struct ModelsR4.QuestionnaireResponse
import PlainlyShared
import SpeziFoundation
import SpeziHealthKit
import SwiftUI


struct StudyHomeView: View {
    private let preloadedStudy: InProgressStudy?
    
    @LocalPreference(.resourceLimit) private var resourceLimit
    @Environment(PlainlyStandard.self) private var standard
    @Environment(HealthKit.self) private var healthKit
    @Environment(FHIRInterpretationModule.self) private var fhirInterpretationModule
    @Environment(FirebaseUpload.self) private var uploader: FirebaseUpload?
    @WaitingState private var waitingState
    
    @State private var isPresentingQuestionnaire = false
    @State private var questionnaireResponse: QuestionnaireResponse?
    
    @State private var isPresentingEarliestHealthRecords = false
    @State private var isPresentingQRCodeScanner = false
    
    @State private var isPresentingUserStudyChatView = false
    
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
            .fullScreenCover(isPresented: $isPresentingUserStudyChatView) {
                chatSheetContent
            }
    }

    private var observedContent: some View {
        presentationContent
            .onAppear {
                logAppearance()
            }
            .onChange(of: fhirInterpretationModule.currentStudy?.study.id) { oldValue, newValue in
                logStudySelectionChange(from: oldValue, to: newValue)
            }
            .onChange(of: isPresentingQuestionnaire) { _, isPresented in
                logQuestionnairePresentation(isPresented)
            }
            .onChange(of: questionnaireResponse != nil) { _, hasResponse in
                logQuestionnaireResponseAvailability(hasResponse)
            }
            .onChange(of: isPresentingUserStudyChatView) { _, isPresented in
                logChatPresentation(isPresented)
            }
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
                study: currentStudy.study,
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
            UserStudyChatView(model: .init(
                inProgressStudy: currentStudy,
                initialQuestionnaireResponse: questionnaireResponse,
                interpretationModule: fhirInterpretationModule,
                uploader: uploader
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
    
    private var primaryActionButton: some View {
        PrimaryActionButton {
            if fhirInterpretationModule.currentStudy != nil {
                if isMissingPreChatQuestionnaire {
                    AppDiagnostics.questionnaire.notice("Presenting required initial questionnaire")
                    isPresentingQuestionnaire = true
                    return
                }
                // the HealthKit permissions should already have been granted via the onboarding, but we re-request them here, just in case,
                // to make sure everything is in a proper state when the study gets launched.
                AppDiagnostics.healthRecords.notice("Refreshing Health Records authorization before chat")
                do {
                    try await healthKit.askForAuthorization()
                    AppDiagnostics.healthRecords.notice(
                        "Health Records authorization refresh returned before chat"
                    )
                } catch {
                    AppDiagnostics.healthRecords.logError(
                        error,
                        context: "Refreshing Health Records authorization before chat"
                    )
                    throw error
                }
                await fhirInterpretationModule.updateSchemas()
                AppDiagnostics.chat.notice("Presenting study chat after schema update")
                isPresentingUserStudyChatView = true
            } else {
                AppDiagnostics.study.notice("Presenting study QR code scanner")
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

    init(study: Study, config: StudyConfig, userInfo: [String: String]) {
        preloadedStudy = InProgressStudy(study: study, config: config, userInfo: userInfo)
    }
    
    init() {
        preloadedStudy = nil
    }

    private func logSelectedStudy(_ studyID: Study.ID) {
        let description = String(describing: studyID)
        AppDiagnostics.study.notice(
            "Study selected from QR code; study=\(description, privacy: .public)"
        )
    }

    @MainActor
    private func processStudyQRCode(_ payload: String) -> QRCodeScanningResponse {
        guard fhirInterpretationModule.currentStudy == nil else {
            return .stopScanning
        }
        do {
            let scanResult = try StudyQRCodeHandler.processQRCode(payload: payload)
            isPresentingQRCodeScanner = false
            fhirInterpretationModule.currentStudy = .init(
                study: scanResult.study,
                config: scanResult.studyConfig,
                userInfo: scanResult.userInfo
            )
            logSelectedStudy(scanResult.study.id)
            return .stopScanning
        } catch {
            AppDiagnostics.study.logError(error, context: "Selecting study from QR code")
            return .continueScanning
        }
    }

    private func logAppearance() {
        AppDiagnostics.study.notice("""
            Study home appeared; hasPreloadedStudy=\(self.preloadedStudy != nil); \
            hasCurrentStudy=\(self.fhirInterpretationModule.currentStudy != nil); hasUploader=\(self.uploader != nil)
            """)
    }

    private func logQuestionnairePresentation(_ isPresented: Bool) {
        AppDiagnostics.questionnaire.notice(
            "Questionnaire presentation changed; isPresented=\(isPresented)"
        )
    }

    private func logQuestionnaireResponseAvailability(_ hasResponse: Bool) {
        AppDiagnostics.questionnaire.notice(
            "Questionnaire response availability changed; hasResponse=\(hasResponse)"
        )
    }

    private func logChatPresentation(_ isPresented: Bool) {
        AppDiagnostics.chat.notice(
            "Chat presentation changed; isPresented=\(isPresented)"
        )
    }

    @MainActor
    private func prepareInitialStudyState() async {
        if let preloadedStudy {
            logApplyingPreloadedStudy(preloadedStudy.study.id)
            fhirInterpretationModule.currentStudy = preloadedStudy
        }
        AppDiagnostics.study.notice("Study home initial preparation started")
        await standard.fetchRecordsFromHealthKit()
        await fhirInterpretationModule.updateSchemas()
        AppDiagnostics.study.notice("Study home initial preparation completed")
    }

    private func logStudySelectionChange(from oldValue: Study.ID?, to newValue: Study.ID?) {
        let oldDescription = oldValue.map { String(describing: $0) } ?? "none"
        let newDescription = newValue.map { String(describing: $0) } ?? "none"
        AppDiagnostics.study.notice("""
            Selected study changed; old=\(oldDescription, privacy: .public); \
            new=\(newDescription, privacy: .public)
            """)
    }

    private func logApplyingPreloadedStudy(_ studyID: Study.ID) {
        let description = String(describing: studyID)
        AppDiagnostics.study.notice(
            "Applying preloaded study; study=\(description, privacy: .public)"
        )
    }

    private func preloadInitialQuestionnaire() async {
        guard let study = fhirInterpretationModule.currentStudy?.study else {
            AppDiagnostics.questionnaire.info("Questionnaire preload skipped because no study is selected")
            return
        }
        do {
            guard let url = try study.initialQuestionnaireURL(in: .main) else {
                AppDiagnostics.questionnaire.info(
                    "Questionnaire preload not required; study=\(study.id, privacy: .public)"
                )
                return
            }
            _ = try await QuestionnaireLoader.shared.questionnaire(from: url)
            AppDiagnostics.questionnaire.info(
                "Questionnaire preload completed; study=\(study.id, privacy: .public)"
            )
        } catch is CancellationError {
            AppDiagnostics.questionnaire.info(
                "Questionnaire preload cancelled; study=\(study.id, privacy: .public)"
            )
        } catch {
            AppDiagnostics.questionnaire.logError(error, context: "Questionnaire preload")
        }
    }
}
