//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

import struct ModelsR4.QuestionnaireResponse
import PlainlyShared
import SpeziChat
import SpeziLLM
import SpeziLLMOpenAI
import SpeziQuestionnaire
import SwiftUI


private enum UserStudyResponseGenerationError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        String(localized: "Plainly did not receive a chat response. Please try again.")
    }
}


/// View model for the StudyChatView.
///
/// This view model coordinates between the UI and the FHIRMultipleResourceInterpreter.
/// It provides UI-specific computed properties and methods while delegating
/// LLM operations and persistence to the underlying interpreter.
@MainActor
@Observable
final class StudyChatViewModel: Sendable {
    /// The current state of the survey navigation
    enum NavigationState: Equatable {
        case introduction
        case task(task: Study.Task, taskIdx: Int, numTotalTasks: Int, taskState: TaskState)
        case completed
        
        enum TaskState {
            case chatting
            case answeringSurvey
        }
        
        struct TitleConfig {
            let title: String
            let subtitle: String?
        }
        
        /// The participant-facing position of a task, e.g. `Task 2 of 5`.
        static func taskTitle(taskIdx: Int, numTotalTasks: Int) -> String {
            "Task \(taskIdx + 1) of \(numTotalTasks)"
        }

        func titleConfig(in study: Study) -> TitleConfig {
            let regularConfig = switch self {
            case .introduction:
                TitleConfig(title: "Introduction", subtitle: study.title)
            case let .task(task, taskIdx, numTotalTasks, taskState: _):
                TitleConfig(
                    title: Self.taskTitle(taskIdx: taskIdx, numTotalTasks: numTotalTasks),
                    subtitle: { () -> String in
                        if let taskTitle = task.title {
                            "\(study.title) — \(taskTitle)"
                        } else {
                            study.title
                        }
                    }()
                )
            case .completed:
                TitleConfig(title: "Study Completed", subtitle: study.title)
            }
            return switch study.chatTitleConfig {
            case .default:
                regularConfig
            case .studyTitle:
                TitleConfig(title: study.title, subtitle: nil)
            }
        }
    }
    
    /// The stages the completion sheet moves through once the session ends.
    enum CompletionState: Hashable, Sendable {
        /// The report is being uploaded.
        case submitting
        /// The report reached Firebase Storage.
        case submitted
        /// The upload failed and the report was kept for a later attempt.
        case retained
    }

    enum PresentedSheet: Hashable, Identifiable {
        case instructions
        case survey
        case completion
        
        var id: some Hashable {
            self
        }
    }
    
    private let uploader: FirebaseUpload?
    private let pendingReports: PendingReportStore?
    
    private let interpretationModule: FHIRInterpretationModule
    
    private var interpreter: FHIRMultipleResourceInterpreter {
        interpretationModule.multipleResourceInterpreter
    }
    private var resourceSummarizer: FHIRResourceSummarizer {
        interpretationModule.resourceSummarizer
    }
    
    private(set) var processingState: ProcessingState = .processingSystemPrompts
    
    /// The current navigation state of the study
    private(set) var navigationState: NavigationState = .introduction
    
    /// The currently-presented sheet
    var presentedSheet: PresentedSheet?
    
    /// Whether the chat view is currently displaying the "End Chat?" alert.
    ///
    /// This alert is presented when the user taps the continue button while in a study that contains no tasks.
    var isShowingConfirmEndChatAlert = false
    
    /// How far the session's report has got, which the completion sheet animates between.
    private(set) var completionState: CompletionState = .submitting

    /// Controls the visibility of the dismiss confirmation dialog
    var isDismissDialogPresented = false
    
    /// Indicates if the LLM is currently processing or generating a response
    /// This property directly reflects the LLM session's state
    var isProcessing: Bool {
        llmSession.state.representation == .processing
    }
    
    let inProgressStudy: InProgressStudy
    var study: Study {
        inProgressStudy.study
    }
    /// The response to the Study's initial questionnaire, if any.
    private let initialQuestionnaireResponse: ModelsR4.QuestionnaireResponse?
    private let studyStartTime = Date.now
    private var taskStartTimes: [Study.Task.ID: Date] = [:]
    private var taskEndTimes: [Study.Task.ID: Date] = [:]
    private var assistantMessagesByTask = LimitedCollectionDictionary<Study.Task.ID, String>()
    
    
    /// Creates a new view model for managing a user study chat session
    ///
    /// - Parameters:
    ///   - survey: The survey configuration to use for this study
    ///   - interpreter: The FHIR interpreter to use for chat functionality
    ///   - resourceSummarizer: The FHIR resource summary provider for generating summaries of FHIR resources
    init(
        inProgressStudy: InProgressStudy,
        initialQuestionnaireResponse: ModelsR4.QuestionnaireResponse?,
        interpretationModule: FHIRInterpretationModule,
        uploader: FirebaseUpload?,
        pendingReports: PendingReportStore?
    ) {
        self.inProgressStudy = inProgressStudy
        self.initialQuestionnaireResponse = initialQuestionnaireResponse
        self.interpretationModule = interpretationModule
        self.uploader = uploader
        self.pendingReports = pendingReports
        configureMessageLimits()
    }
    
    /// Cancels any ongoing operations and dismisses the current view
    ///
    /// - Parameter dismiss: The dismiss action from the environment to close the view
    func handleDismiss(dismiss: DismissAction) {
        interpreter.cancel()
        resetStudy()
        dismiss()
    }
    
    /// Handles the submission of survey answers for a task within the survey.
    ///
    /// This method processes the user's answers. If `task` is the current task, it also advances to the next task in the survey sequence.
    ///
    /// - parameter responses: The responses the participant gave to the task's questionnaire.
    /// - parameter task: The ``SurveyTask`` to which the responses belong.
    func submitSurveyResponses(_ responses: QuestionnaireResponses, for task: Study.Task) {
        let isCurrentTask = task == currentTask
        if isCurrentTask {
            taskEndTimes[task.id] = .now
        }
        inProgressStudy.responses[task.id] = responses
        guard isCurrentTask else {
            presentedSheet = nil
            return
        }
        advanceToNextTask()
    }
    
    /// Resets the study to its initial state
    ///
    /// This method clears all survey answers and resets the navigation state,
    /// bringing the study back to its starting point.
    func resetStudy() {
        inProgressStudy.responses.removeAll()
        taskStartTimes.removeAll()
        taskEndTimes.removeAll()
        navigationState = .introduction
    }
    
    /// Starts the survey portion of the study
    ///
    /// This method initializes the survey process if it hasn't already been started.
    ///
    /// - returns: `true` if the survey was successfully started, `false` if not (because the study contains no tasks)
    func startStudy() -> Bool {
        guard let task = study.tasks.first else {
            return false
        }
        begin(task, at: 0)
        return true
    }
    
    
    func endStudy() {
        navigationState = .completed
        Task {
            completionState = .submitting
            presentedSheet = .completion
            completionState = await uploadReport() ? .submitted : .retained
        }
    }

    /// Closes the confirmation once the participant acknowledges it.
    func finishCompletedStudy() {
        presentedSheet = nil
    }
    
    private func advanceToNextTask() {
        guard let currentTaskIdx = study.tasks.firstIndex(where: { $0.id == currentTaskId }) else {
            return
        }
        let nextTaskIdx = study.tasks.index(after: currentTaskIdx)
        guard let nextTask = study.tasks[safe: nextTaskIdx] else {
            // no next task.
            endStudy()
            return
        }
        begin(nextTask, at: nextTaskIdx)
    }

    /// Starts `task`, presenting whichever step it begins with.
    ///
    /// A task without a chat has nothing to introduce, so its questions are presented right away. When
    /// it follows another task's questions the sheet simply carries on, without returning to the chat.
    private func begin(_ task: Study.Task, at taskIdx: Int) {
        let taskState: NavigationState.TaskState = task.hasChat || task.questions.isEmpty
            ? .chatting
            : .answeringSurvey
        navigationState = .task(
            task: task,
            taskIdx: taskIdx,
            numTotalTasks: study.tasks.count,
            taskState: taskState
        )
        taskStartTimes[task.id] = .now
        switch taskState {
        case .chatting:
            presentedSheet = .instructions
        case .answeringSurvey:
            presentedSheet = .survey
        }
    }
    
    /// Advances the user's progression within the study.
    ///
    /// Depending on the current ``navigationState``, this function will either advance within the current task (e.g., move from the chat phase to the survey)
    /// or advance within the overall study (e.g., move from task N's survey to task N+1's instructions).
    ///
    /// If the study is already completed, this function does nothing.
    func advance() {
        switch navigationState {
        case .introduction:
            if !startStudy() {
                // the survey was not started, because the study contained no tasks.
                // in this case, the attempt to advance will be interpreted as the user attempting to complete the study,
                // so we ask if they really want to do that.
                isShowingConfirmEndChatAlert = true
            }
        case let .task(task, taskIdx, numTotalTasks, taskState):
            switch taskState {
            case .chatting:
                if !task.questions.isEmpty {
                    // we're currently in the chat phase, and there are questions, so we start the survey
                    navigationState = .task(task: task, taskIdx: taskIdx, numTotalTasks: numTotalTasks, taskState: .answeringSurvey)
                    presentedSheet = .survey
                } else {
                    // we're in the chat phase, and there are no questions, so we go to the next task
                    advanceToNextTask()
                }
            case .answeringSurvey:
                // we're answering the survey, so advancing from there means going to the next task
                advanceToNextTask()
            }
        case .completed:
            // if we've already completed the survey, there is nowhere else to go
            return
        }
    }
}


extension StudyChatViewModel {
    var isTaskIntructionButtonDisabled: Bool {
        study.tasks.first { $0.id == currentTaskId }?.instructions == nil
    }
    
    /// Returns the current task if one is active
    var currentTask: Study.Task? {
        study.tasks.first { $0.id == currentTaskId }
    }
    
    private var currentTaskId: Study.Task.ID? {
        switch navigationState {
        case let .task(task, taskIdx: _, numTotalTasks: _, taskState: _):
            task.id
        case .introduction, .completed:
            nil
        }
    }
    
    var currentTaskIdx: Int? {
        study.tasks.firstIndex { $0.id == currentTaskId }
    }
    
    var userDisplayableCurrentTaskIdx: Int? {
        currentTaskIdx.map { $0 + 1 }
    }

    /// The position of the current task, titling its questions the same way the chat titles the task.
    var currentTaskTitle: String? {
        currentTaskIdx.map { NavigationState.taskTitle(taskIdx: $0, numTotalTasks: study.tasks.count) }
    }
}


extension StudyChatViewModel {
    /// Determines whether to display a typing indicator in the chat interface.
    ///
    /// Only shown while waiting for the response; once it starts streaming in, the message itself
    /// already shows that something is happening.
    var showTypingIndicator: Bool {
        processingState.isProcessing && !isResponseStreamingIn
    }

    /// Whether the assistant has started streaming visible content for its current response.
    ///
    /// A message carrying tool calls has no content of its own yet, so it still counts as waiting.
    private var isResponseStreamingIn: Bool {
        guard let lastMessage = llmSession.context.last,
              case let .assistant(toolCalls) = lastMessage.role,
              toolCalls.isEmpty else {
            return false
        }
        return !lastMessage.content.isEmpty
    }
    
    // Whether the chat input should currently be enabled, i.e. whether the user should currently be able to write (and submit) chat messages
    var shouldEnableChatInput: Bool {
        // Always disable during processing
        if isProcessing {
            return false
        }
        // If no capacity range is configured for this task, enable chat input
        if !hasConfiguredCapacityForCurrentTask {
            return true
        }
        // Disable when the maximum number of messages is reached
        return !isMaxAssistantMessagesReached
    }
    
    var shouldEnableContinueToNextTaskAction: Bool {
        if isProcessing {
            // Always disable during processing
            return false
        }
        if !hasConfiguredCapacityForCurrentTask {
            // If no capacity range is configured for this task, enable toolbar
            return true
        }
        // Disable if the minimum number of messages is not met
        return isMinAssistantMessagesReached
    }
}


extension StudyChatViewModel {
    /// Direct access to the current LLM session for observing state changes
    var llmSession: LLMOpenAISession {
        guard let llmSession = interpreter.llmSession as? LLMOpenAISession else {
            preconditionFailure("Plainly requires a SpeziLLM OpenAI session.")
        }
        return llmSession
    }
}


extension StudyChatViewModel {
    private var isMaxAssistantMessagesReached: Bool {
        currentTaskId.map { assistantMessagesByTask.isMaxReached(forKey: $0) } ?? false
    }

    private var isMinAssistantMessagesReached: Bool {
        currentTaskId.map { assistantMessagesByTask.isMinReached(forKey: $0) } ?? false
    }

    private var hasConfiguredCapacityForCurrentTask: Bool {
        currentTaskId.map { assistantMessagesByTask.hasConfiguredCapacity(forKey: $0) } ?? false
    }
    
    private func configureMessageLimits() {
        for task in study.tasks {
            guard let limits = task.assistantMessagesLimit else {
                assistantMessagesByTask.setUnlimitedCapacity(forKey: task.id)
                continue
            }
            do {
                try assistantMessagesByTask.setCapacityRange(minimum: limits.lowerBound, maximum: limits.upperBound, forKey: task.id)
            } catch {
                AppDiagnostics.configuration.logError(error, context: "Configuring task message limit")
            }
        }
    }
}


extension StudyChatViewModel {
    private var shouldGenerateResponse: Bool {
        if llmSession.state == .generating || isProcessing {
            return false
        }
        // Check if the last message is from a user (needs a response)
        let lastMessageIsUser = interpreter.llmSession.context.last?.role == .user
        // Check if there are no assistant messages yet (initial prompt needs a response)
        let noAssistantMessages = !interpreter.llmSession.context.contains(where: { $0.role == .assistant() })
        // Generate if last message is from user or if there are no assistant messages yet
        return lastMessageIsUser || noAssistantMessages
    }
    
    private func updateProcessingState() async {
        switch llmSession.state {
        case .error(let error):
            AppDiagnostics.chat.logError(error, context: "Updating chat processing state")
            // Alerts and sheets can not be displayed at the same time.
            if presentedSheet != nil {
                // We have to first dismiss all sheets.
                presentedSheet = nil
                // Wait for animation to complete
                try? await Task.sleep(for: .seconds(1))
                // Re-set the error state.
                llmSession.state = .generating
                try? await Task.sleep(for: .seconds(0.5))
                llmSession.state = .error(error: error)
            }
            processingState = .error
        default:
            processingState = await processingState.calculateNewProcessingState(basedOn: llmSession)
        }
    }

    /// Generates an assistant response if appropriate for the current context
    ///
    /// This method checks if a response is needed and if so, delegates
    /// to the interpreter to generate the actual response.
    func generateAssistantResponse() async throws -> LLMContextEntity? {
        let correlationID = AppDiagnostics.correlationID()
        await updateProcessingState()
        processingState = await processingState.calculateNewProcessingState(basedOn: llmSession)
        guard shouldGenerateResponse else {
            return nil
        }
        processingState = .processingSystemPrompts
        return try await requestAssistantResponse(correlationID: correlationID)
    }

    private func requestAssistantResponse(correlationID: String) async throws -> LLMContextEntity {
        do {
            let response = try await interpreter.generateAssistantResponse()
            try Task.checkCancellation()
            guard let response, response.role == .assistant() else {
                throw UserStudyResponseGenerationError.emptyResponse
            }
            await updateProcessingState()
            processingState = await processingState.calculateNewProcessingState(basedOn: llmSession)
            if let currentTaskId {
                try? assistantMessagesByTask.append(response.id.uuidString, forKey: currentTaskId)
            }
            return response
        } catch let error as CancellationError {
            throw error
        } catch {
            AppDiagnostics.chat.logError(
                error,
                context: "Assistant response generation",
                correlationID: correlationID
            )
            processingState = .error
            throw error
        }
    }
}


// MARK: Model + Report

extension StudyChatViewModel {
    /// Uploads the report using the firebase backend, if available
    ///
    /// - returns: a flag indicating whether the upload was successful.
    private func uploadReport() async -> Bool {
        guard let uploader else {
            return false
        }
        do {
            guard let reportFile = try await generateStudyReportFile() else {
                AppDiagnostics.report.error("Study report generation returned no file")
                return false
            }
            do {
                try await uploader.uploadReport(at: reportFile, for: study)
                try? FileManager.default.removeItem(at: reportFile)
                return true
            } catch {
                AppDiagnostics.report.logError(error, context: "Study report upload")
                do {
                    // Retaining moves the file. If that fails the report stays where it is rather than
                    // being deleted, because it holds the only copy of the session's answers.
                    try pendingReports?.retainForRetry(reportAt: reportFile, for: study)
                } catch {
                    AppDiagnostics.report.logError(error, context: "Retaining study report for a later upload")
                }
                return false
            }
        } catch {
            AppDiagnostics.report.logError(error, context: "Study report generation")
            return false
        }
    }
    
    /// Generates a temporary file URL containing the study report
    ///
    /// - Returns: The URL of the generated report file, or nil if generation fails
    func generateStudyReportFile() async throws -> URL? {
        guard let studyReport = await generateStudyReport() else {
            return nil
        }
        let tempDir = FileManager.default.temporaryDirectory
        let reportURL = tempDir.appendingPathComponent("survey_report_\(study.id.lowercased()).json")
        try studyReport.write(to: reportURL)
        return reportURL
    }
    
    private func generateStudyReport() async -> Data? {
        let report = StudyReport(
            metadata: .init(
                studyID: study.id,
                startTime: studyStartTime,
                endTime: .now,
                userInfo: inProgressStudy.userInfo,
                llmConfig: .init(model: study.llmModel)
            ),
            initialQuestionnaireResponse: initialQuestionnaireResponse,
            fhirResources: await getFHIRResources(),
            timeline: generateTimeline()
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            return data
        } catch {
            AppDiagnostics.report.logError(error, context: "Study report encoding")
            return nil
        }
    }

    private func generateTimeline() -> [StudyReport.TimelineEvent] {
        var timeline: [StudyReport.TimelineEvent] = interpreter.llmSession.context.chat.map { message in
            .chatMessage(.init(
                timestamp: message.date,
                role: message.role.rawValue,
                content: message.content
            ))
        }
        timeline.append(contentsOf: study.tasks.compactMap { task -> StudyReport.TimelineEvent? in
            guard let taskStartTime = taskStartTimes[task.id], let taskEndTime = taskEndTimes[task.id] else {
                return nil
            }
            return .surveyTask(.init(
                taskId: task.id,
                startedAt: taskStartTime,
                completedAt: taskEndTime,
                duration: taskEndTime.timeIntervalSince(taskStartTime),
                questions: surveyQuestions(for: task)
            ))
        })
        return timeline.sorted()
    }

    /// The task's answers in the flat report shape.
    private func surveyQuestions(for task: Study.Task) -> [StudyReport.TimelineEvent.SurveyQuestion] {
        let responses = inProgressStudy.responses[task.id]
        return task.questions.enumerated().map { index, question in
            let value = responses?.responses[Study.Task.questionId(at: index) as Questionnaire.Task.ID].value
            return StudyReport.TimelineEvent.SurveyQuestion(
                questionText: question.title,
                answer: value.map { question.legacyAnswer(from: $0) } ?? Questionnaire.Task.legacyUnansweredValue,
                isOptional: question.isOptional
            )
        }
    }

    private func getFHIRResources() async -> StudyReport.FHIRResources {
        let llmRelevantResources = interpreter.fhirStore.llmRelevantResources
            .map { resource in
                StudyReport.FullFHIRResource(resource.versionedResource)
            }
        let allResources = await interpreter.fhirStore.allResources.mapAsync { resource in
            let summary = await resourceSummarizer.cachedSummary(forResource: resource)
            return StudyReport.PartialFHIRResource(
                id: resource.id,
                resourceType: resource.resourceType,
                displayName: resource.displayName,
                dateDescription: resource.date?.description,
                summary: summary?.description
            )
        }
        return StudyReport.FHIRResources(
            llmRelevantResources: FeatureFlags.exportRawJSONFHIRResources ? llmRelevantResources : [],
            allResources: allResources
        )
    }
}
