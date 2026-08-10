//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation


extension Study.Task {
    /// The user-selectable options associated with a ``TaskQuestionType/scale(responseOptions:)``
    public struct AnswerOptions: Hashable, RandomAccessCollection, ExpressibleByArrayLiteral, Sendable {
        private let storage: [String]
        
        public var startIndex: Int {
            storage.startIndex
        }
        public var endIndex: Int {
            storage.endIndex
        }
        
        public init(_ other: some Sequence<String>) {
            storage = Array(other)
        }
        
        public init(arrayLiteral elements: String...) {
            storage = elements
        }
        
        public subscript(position: Int) -> String {
            storage[position]
        }
    }
}


extension Study.Task.AnswerOptions {
    /// A clarity scale.
    public static let clarityScale: Self = [
        "Very clear",
        "Somewhat clear",
        "Neither clear nor unclear",
        "Somewhat unclear",
        "Very unclear"
    ]

    /// An effectiveness scale.
    public static let effectivenessScale: Self = [
        "Very effective",
        "Somewhat effective",
        "Neither clear nor unclear",
        "Somewhat ineffective",
        "Very ineffective"
    ]
    
    /// A confidence scale.
    public static let confidentnessScale: Self = [
        "Very confident",
        "Somewhat confident",
        "Neither confident nor unconfident",
        "Somewhat unconfident",
        "Very unconfident"
    ]

    /// A comparison scale.
    public static let comparisonScale: Self = [
        "Significantly better",
        "Slightly better",
        "No change",
        "Slightly worse",
        "Significantly worse"
    ]

    /// An ease scale.
    public static let balancedEaseScale: Self = [
        "Very easy",
        "Somewhat easy",
        "Neither easy nor difficult",
        "Somewhat difficult",
        "Very difficult"
    ]

    /// A frequency scale.
    public static let frequencyOptions: Self = [
        "Always",
        "Often",
        "Sometimes",
        "Rarely",
        "Never"
    ]
}
