//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import GroveLLM
import PlainlyVoice
import SwiftUI
import UIKit


/// The voice-mode conversation, where the chat would otherwise be; the surrounding study screen is unchanged.
struct StudyVoiceView: View {
    @Environment(LLMRunner.self) private var llmRunner
    @Environment(\.scenePhase) private var scenePhase

    let model: StudyChatViewModel

    @State private var resumeTask: Task<Void, Never>?

    private var voice: any VoicePresenter {
        model.voice(using: llmRunner)
    }

    var body: some View {
        VoiceConversationView(presenter: voice)
            .background(Color(.systemBackground))
            // Talking gives the screen no touches, so it would lock mid-conversation.
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .task {
                // A sheet can already be up when the conversation begins; the change hook below only sees later ones.
                voice.isPaused = model.presentedSheet != nil
                await voice.start()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                resumeTask?.cancel()
                resumeTask = nil
                voice.stop()
            }
            // Instructions and surveys take the participant away from the conversation; it waits for them.
            .onChange(of: model.presentedSheet) { _, sheet in
                voice.isPaused = sheet != nil
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    resumeTask?.cancel()
                    voice.stop()
                case .active:
                    resumeTask?.cancel()
                    // Kept, so leaving the screen before it runs keeps a session from starting off-screen.
                    resumeTask = Task {
                        guard !Task.isCancelled else {
                            return
                        }
                        await voice.start()
                    }
                default:
                    break
                }
            }
    }
}
