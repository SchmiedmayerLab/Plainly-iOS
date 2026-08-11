//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A localized LLM prompt for FHIR resources.
///
/// Prompts are defined by the study that is being run; they cannot be customized on the device.
public struct FHIRPrompt: Hashable, Sendable {
    /// Placeholder for FHIR resource in prompts.
    public static let fhirResourcePlaceholder = "{{FHIR_RESOURCE}}"
    /// Placeholder for the current locale in a prompt
    public static let localePlaceholder = "{{LOCALE}}"

    /// The prompt text, appended with a localized message that adapts to the user's language settings.
    public let promptText: String


    public init(promptText: String) {
        self.promptText = promptText
    }


    /// Creates a prompt based in the variable input.
    ///
    /// Use ``FHIRPrompt/fhirResourcePlaceholder`` and ``FHIRPrompt/localePlaceholder`` to define the elements that should be replaced.
    /// - Parameters:
    ///   - resource: The resource that should be inserted in the prompt.
    ///   - locale: The current locale that should be inserted in the prompt.
    /// - Returns: The constructed prompt.
    public func prompt(withFHIRResource resource: String, locale: String = Locale.preferredLanguages[0]) -> String {
        promptText
            .replacingOccurrences(of: FHIRPrompt.fhirResourcePlaceholder, with: resource)
            .replacingOccurrences(of: FHIRPrompt.localePlaceholder, with: locale)
    }
}


extension FHIRPrompt: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(promptText: value)
    }
}
