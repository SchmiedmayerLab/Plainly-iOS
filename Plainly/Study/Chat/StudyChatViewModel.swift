//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//


import GroveFoundation
import GroveLLM
import GroveLLMOpenAI
import GroveQuestionnaire
import struct ModelsR4.QuestionnaireResponse
import PlainlyShared
import PlainlyVoice
import SwiftUI

// swiftlint:disable file_length


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
        case explanationLevel
        
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
    /// Whether the participant has taken over how detailed an answer should be.
    ///
    /// Off until they say otherwise, so a study reads the way its own instructions ask for by default. Kept
    /// between sessions, along with the level itself.
    var isExplanationLevelEnabled: Bool {
        didSet {
            LocalPreferencesStore.standard[.explanationLevelEnabled] = isExplanationLevelEnabled
        }
    }

    /// How much clinical detail the participant asked for, starting from what the study pre-selects.
    ///
    /// Only meaningful for a study that sets ``PlainlyShared/Study/defaultExplanationLevel``; the chat hides
    /// the control otherwise, and the value then never reaches a request.
    var explanationLevel: ExplanationLevel {
        didSet {
            LocalPreferencesStore.standard[.explanationLevel] = explanationLevel.rawValue
        }
    }
    /// Experimental: lets a chat study switch into the voice conversation and back, on the same chat.
    var isVoiceModeEnabled: Bool {
        didSet {
            LocalPreferencesStore.standard[.voiceModeEnabled] = isVoiceModeEnabled
        }
    }

    private let studyStartTime = Date.now
    private var taskStartTimes: [Study.Task.ID: Date] = [:]
    private var taskEndTimes: [Study.Task.ID: Date] = [:]
    private var assistantMessagesByTask = LimitedCollectionDictionary<Study.Task.ID, String>()
    @ObservationIgnored private var voicePresenter: (any VoicePresenter)?
    // How long the chat was when the voice conversation was made; more chat since means a new hand-over.
    @ObservationIgnored private var voiceContextCount = 0
    @ObservationIgnored private var retiredVoiceTurns: [VoiceTurn] = []
    
    
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
        // The participant's own choice outlives the session; the study's default is only where they start.
        let store = LocalPreferencesStore.standard
        self.isExplanationLevelEnabled = store[.explanationLevelEnabled]
        self.isVoiceModeEnabled = store[.voiceModeEnabled]
        self.explanationLevel = store[.explanationLevel]
            .flatMap(ExplanationLevel.init(rawValue:))
            ?? inProgressStudy.study.defaultExplanationLevel
            ?? .balanced
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
        voicePresenter?.stop()
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
        // The conversation lives on the interpretation module, which outlasts this view model, so clearing the
        // study's own state is not what the participant was told would happen.
        interpretationModule.startNewConversation()
        processingState = .completed
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
        voicePresenter?.stop()
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
            // A task without instructions has nothing to present, and the sheet's only dismiss button
            // lives in the content that would not exist.
            if task.instructions != nil {
                presentedSheet = .instructions
            }
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
              case .assistant = lastMessage.role else {
            return false
        }
        return !lastMessage.content.isEmpty
    }
    
    // Whether the chat input should currently be enabled, i.e. whether the user should currently be able to write (and submit) chat messages
    /// Whether the composer takes input: only a task that has reached its message cap closes it.
    var shouldEnableChatInput: Bool {
        !hasConfiguredCapacityForCurrentTask || !isMaxAssistantMessagesReached
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
    /// How many conversations the interpretation module has started, so the chat can notice its own being
    /// replaced by a schema update and ask for an answer on the new one.
    var conversationGeneration: Int {
        interpretationModule.conversationGeneration
    }

    /// Direct access to the current LLM session for observing state changes
    var llmSession: LLMOpenAISession {
        guard let llmSession = interpreter.llmSession as? LLMOpenAISession else {
            preconditionFailure("Plainly requires a GroveLLM OpenAI session.")
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
        let noAssistantMessages = !interpreter.llmSession.context.contains(where: { $0.role == .assistant })
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
        ensureResponseInput()
        if study.defaultExplanationLevel != nil && isExplanationLevelEnabled {
            // Applied per request rather than when the participant picks: a schema update rebuilds the context,
            // and the choice has to survive that without the participant setting it again.
            llmSession.context.setExplanationLevel(explanationLevel)
        }
        // Spoken answers have to be short and plain; typed ones keep the study's own style, also after switching back.
        if usesVoice {
            llmSession.context.set(systemMessage: InternalInput.voiceModeNote, id: InternalInput.voiceModeNoteID)
        } else {
            llmSession.context.removeAll { $0.id == InternalInput.voiceModeNoteID }
        }
        await updateProcessingState()
        processingState = await processingState.calculateNewProcessingState(basedOn: llmSession)
        guard shouldGenerateResponse else {
            // A chat that declines to answer looks exactly like one that failed silently, which is the
            // hardest kind of report to act on; the counts say which of the two it happened to be.
            let context = llmSession.context
            AppDiagnostics.chat.notice(
                """
                Assistant response not needed; correlation=\(correlationID, privacy: .public); \
                entities=\(context.count); participantInput=\(context.count(where: \.isParticipantInput)); \
                lastIsAssistant=\(context.last?.role == .assistant)
                """
            )
            return nil
        }
        processingState = .processingSystemPrompts
        return try await requestAssistantResponse(correlationID: correlationID)
    }

    /// Responses requests require input in addition to instructions. The previous transport accepted the
    /// study's system prompt by itself for the opening turn, so add an internal user turn for that one case.
    private func ensureResponseInput() {
        guard llmSession.context.allSatisfy({ $0.role == .system }) else {
            return
        }
        llmSession.context.append(userMessage: InternalInput.conversationStarter, id: InternalInput.conversationStarterID)
    }

    private func requestAssistantResponse(correlationID: String) async throws -> LLMContextEntity {
        do {
            let response = try await interpreter.generateAssistantResponse()
            try Task.checkCancellation()
            guard let response, response.role == .assistant else {
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


// MARK: Voice
extension StudyChatViewModel {
    private enum VoiceTurnError: LocalizedError {
        case noAnswer
        case answerFailed

        var errorDescription: String? {
            switch self {
            case .noAnswer:
                String(localized: "Plainly did not answer in time.")
            case .answerFailed:
                String(localized: "Plainly could not answer that. Please ask again.")
            }
        }
    }

    /// Whether the conversation is spoken: in a voice study, or in a chat study switched over while trying it out.
    var usesVoice: Bool {
        study.resolvedInteractionMode == .voice || (Deployment.isDevelopment && isVoiceModeEnabled)
    }

    /// The mode the conversation ran in, for the report: voice as soon as anything was said by voice.
    var interactionMode: Study.InteractionMode {
        usesVoice || !voiceTurns.isEmpty ? .voice : .chat
    }

    private var voiceTurns: [VoiceTurn] {
        retiredVoiceTurns + ((voicePresenter as? VoiceConversation)?.turns ?? [])
    }

    /// The last few exchanges of the text conversation, or `nil` while the participant has not said anything yet.
    private var conversationSoFar: String? {
        let exchanges = llmSession.context.filter { ($0.isParticipantInput || $0.role == .assistant) && $0.complete && !$0.content.isEmpty }
        guard exchanges.contains(where: \.isParticipantInput) else {
            return nil
        }
        return exchanges.suffix(6)
            .map { "\($0.role == .assistant ? "Assistant" : "Participant"): \($0.content.prefix(600))" }
            .joined(separator: "\n\n")
    }


    /// The voice conversation for this chat, created when voice is entered so a study without voice never pays for it.
    ///
    /// A conversation that went on by text since is handed over afresh: the voice then knows what was said and picks
    /// up from there instead of greeting the participant as if nothing had happened.
    func voice(using llmRunner: LLMRunner) -> any VoicePresenter {
        if let voicePresenter, voicePresenter.phase != .idle || llmSession.context.count == voiceContextCount {
            return voicePresenter
        }
        retiredVoiceTurns += (voicePresenter as? VoiceConversation)?.turns ?? []
        voiceContextCount = llmSession.context.count
        let presenter: any VoicePresenter
        if FeatureFlags.voiceDemo {
            presenter = VoiceDemoPresenter()
        } else {
            let studyId = study.id
            let prompts = study.voicePrompts
            let conversationSoFar = conversationSoFar
            // Greetings are spoken outside the session's instructions, so a hand-over carries the conversation itself.
            let greeting: String?
            if let conversationSoFar {
                greeting = prompts.handoff.map { "\($0)\n\n<conversation>\n\(conversationSoFar)\n</conversation>" }
            } else {
                greeting = prompts.greeting
            }
            presenter = VoiceConversation(
                // The study's prompts, with its chat prompt attached as background; the answers still come from the chat.
                configuration: .init(
                    instructions: prompts.sessionInstructions(
                        studyPrompt: study.interpretMultipleResourcesPrompt.promptText,
                        conversationSoFar: conversationSoFar
                    ),
                    toolName: "ask_plainly",
                    greeting: greeting,
                    bridge: prompts.bridge,
                    reassurance: prompts.reassurance
                ),
                llmRunner: llmRunner,
                mint: { request in
                    try await FirebaseRealtimeSessions.mint(request, studyId: studyId)
                },
                forward: { [weak self] transcript in
                    guard let self else {
                        throw CancellationError()
                    }
                    return try await self.forwardVoiceTurn(transcript)
                }
            )
        }
        voicePresenter = presenter
        return presenter
    }

    /// Types the spoken turn into the chat and waits for the answer the chat pipeline produces for it.
    private func forwardVoiceTurn(_ transcript: String) async throws -> String {
        guard shouldEnableChatInput else {
            return String(localized: "You have reached the message limit for this task. Please continue to the next task.")
        }
        let session = llmSession
        // A failure left over from an earlier answer is not this turn's; only one after this turn started counts.
        let failedBefore = processingState == .error
        var hasStarted = false
        let priorCount = session.context.count
        session.context.append(userMessage: transcript)
        defer {
            // What was said by voice is part of what the voice knows; only typing since calls for a new hand-over.
            voiceContextCount = session.context.count
        }
        let deadline = ContinuousClock.now + .seconds(180)
        // The pipeline can pause between two assistant messages for one turn; only an answer that is still the
        // last one a beat later is the answer, so the voice never reads an interim one.
        var candidate: UUID?
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if case .error(let error) = session.state {
                throw error
            }
            if isProcessing || session.state == .generating {
                hasStarted = true
            }
            // The chat reports a failed answer on its own screen, which voice mode does not show.
            if processingState == .error, !failedBefore || hasStarted {
                throw VoiceTurnError.answerFailed
            }
            let answered = session.context.dropFirst(priorCount).last { $0.role == .assistant && $0.complete && !$0.content.isEmpty }
            if let answered, !isProcessing, session.state != .generating {
                if answered.id == candidate {
                    return answered.content
                }
                candidate = answered.id
            } else {
                candidate = nil
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw VoiceTurnError.noAnswer
    }
}


// MARK: Model + Report

extension StudyChatViewModel {
    /// Uploads the report using the firebase backend, if available
    ///
    /// - returns: a flag indicating whether the upload was successful.
    private func uploadReport() async -> Bool {
        let reportFile: URL
        do {
            reportFile = try await StudyReportBuilder(interpretationModule: interpretationModule).writeReport(
                for: inProgressStudy,
                initialQuestionnaireResponse: initialQuestionnaireResponse,
                startTime: studyStartTime,
                interactionMode: interactionMode,
                timeline: generateTimeline()
            )
        } catch {
            AppDiagnostics.report.logError(error, context: "Study report generation")
            return false
        }
        return await StudyReportDelivery(uploader: uploader, pendingReports: pendingReports).deliver(reportAt: reportFile, for: study)
    }

    private func generateTimeline() -> [StudyReport.TimelineEvent] {
        var timeline: [StudyReport.TimelineEvent] = interpreter.llmSession.context.compactMap { entity in
            guard entity.id != InternalInput.conversationStarterID, let message = entity.studyReportChatMessage else {
                return nil
            }
            return .chatMessage(message)
        }
        timeline.append(contentsOf: voiceTurns.map(\.studyReportEvent))
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
            // Instructions have no display title, but their text still belongs in the report.
            let questionText = if case .instructional(let text) = question.kind.variant {
                text
            } else {
                question.title
            }
            return StudyReport.TimelineEvent.SurveyQuestion(
                questionText: questionText,
                answer: value.map { question.legacyAnswer(from: $0) } ?? Questionnaire.Task.legacyUnansweredValue,
                isOptional: question.isOptional
            )
        }
    }
}
