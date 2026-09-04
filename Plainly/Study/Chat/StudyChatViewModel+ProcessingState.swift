//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLLM


extension StudyChatViewModel {
    enum ProcessingState: Equatable {
        case processingSystemPrompts
        case processingFunctionCalls(currentCall: Int, totalCalls: Int)
        case generatingResponse
        case completed
        case error
        
        /// The progress a state has certainly reached the moment it is entered.
        var progress: Double {
            switch self {
            case .processingSystemPrompts:
                return 5
            case let .processingFunctionCalls(current, total):
                let functionCallProgress = total > 0 ? Double(current) / Double(total) : 0
                return 20 + functionCallProgress * 60
            case .generatingResponse:
                return 90
            case .completed:
                return 100
            case .error:
                return 0
            }
        }

        /// How far the bar may creep on time alone before the next real milestone arrives.
        ///
        /// Without streaming the whole answer lands at the end of one long wait, so the creep runs on
        /// towards 90 % instead of stopping at a stage's share and leaves only the last stretch for the finish.
        var creepCeiling: Double {
            switch self {
            case .processingSystemPrompts, .processingFunctionCalls:
                return 90
            case .generatingResponse:
                return 97
            case .completed:
                return 100
            case .error:
                return 0
            }
        }
        
        var statusDescription: String {
            switch self {
            case .processingSystemPrompts:
                "Interpreting message…"
            case let .processingFunctionCalls(current, total):
                "Processing data (\(current)/\(total))…"
            case .generatingResponse:
                "Generating response…"
            case .completed:
                "Processing completed"
            case .error:
                "Encountered an error"
            }
        }
        
        var isProcessing: Bool {
            switch self {
            case .processingSystemPrompts, .processingFunctionCalls:
                true
            case .generatingResponse, .completed, .error:
                false
            }
        }
        
        func calculateNewProcessingState(basedOn llmSession: any LLMSession) async -> ProcessingState {
            // Alerts and sheets can not be displayed at the same time.
            if case .error = await llmSession.state {
                return .error
            }
            guard let lastMessage = await llmSession.context.last else {
                return self
            }
            switch lastMessage.role {
            case .system:
                return .processingSystemPrompts
            case .toolCalls(let toolCalls):
                if !toolCalls.isEmpty {
                    var currentCall: Int
                    let totalCalls: Int
                    if case let .processingFunctionCalls(currentCurrentCall, currentTotalCalls) = self {
                        currentCall = currentCurrentCall
                        totalCalls = currentTotalCalls
                    } else {
                        currentCall = 0
                        totalCalls = 0
                    }
                    
                    currentCall += toolCalls.count
                    return .processingFunctionCalls(
                        currentCall: currentCall,
                        totalCalls: max(currentCall, totalCalls)
                    )
                } else {
                    return .generatingResponse
                }
            case .toolCallResponse:
                var currentCall: Int
                let totalCalls: Int
                if case let .processingFunctionCalls(currentCurrentCall, currentTotalCalls) = self {
                    currentCall = currentCurrentCall
                    totalCalls = currentTotalCalls
                } else {
                    currentCall = 0
                    totalCalls = 0
                }
                currentCall += 1
                return .processingFunctionCalls(
                    currentCall: currentCall,
                    totalCalls: max(currentCall, totalCalls)
                )
            case .assistant, .assistantThinking:
                return .generatingResponse
            case .user:
                return self
            }
        }
    }
}
