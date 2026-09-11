//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The canonical namespace Plainly's own FHIR terminology lives in.
///
/// Every code system Plainly defines resolves under this base, which keeps the codes distinct from
/// SNOMED, LOINC or a study's own systems when they meet in a questionnaire.
public enum PlainlyFHIR {
    /// `https://plainly.stanford.edu/fhir`
    public static let base = URL(string: "https://plainly.stanford.edu/fhir")!

    /// The canonical URL of a Plainly code system.
    public static func codeSystem(_ name: String) -> URL {
        base.appending(path: "CodeSystem").appending(path: name)
    }
}
