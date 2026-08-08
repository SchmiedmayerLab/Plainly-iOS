//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//


import ArgumentParser
import Foundation
import PlainlyShared
import PlainlyStudyDefinitions


private let launchHelp: ArgumentHelp = "The app's launch mode. Defaults to study and should probably not be customized."
private let firebaseHelp: ArgumentHelp = "Firebase GoogleService-Info.plist file that should be embedded into the config file"
private let studiesHelp: ArgumentHelp = "The studies that should be included in the config file. Omit to include all studies."


struct ExportConfigFile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-config",
        abstract: "Creates a UserStudyConfig.plist file that can be embedded into the app",
        discussion: #"""
            Note: in order to create the sample plist file that is commited to the repo, use the following command:
                swift run PlainlyCLI export-config -f '<emulator>' ../Plainly/Supporting\ Files/UserStudyConfig.plist
            """#
    )

    @Option(name: [.customShort("l"), .customLong("launchMode")], help: launchHelp) var launchMode: AppLaunchMode = .study(studyId: nil)

    @Option(name: [.customShort("f"), .customLong("firebaseConfig")], help: firebaseHelp) var firebaseConfigFilePath: URL?

    @Option(name: .customLong("studies"), help: studiesHelp) var includedStudyIds: [String] = Study.allStudies.map(\.id)

    @Argument(help: "Output path where the resulting UserStudyConfig.plist file should be stored") var outputUrl: URL


    func run() throws {
        let issues = Study.validateAllStudies()
        guard issues.isEmpty else {
            throw NSError(domain: "edu.stanford.plainly.CLI", code: 0, userInfo: [
                NSLocalizedDescriptionKey: """
                    The bundled studies are invalid:
                    \(issues.map { "- \($0)" }.joined(separator: "\n"))
                    """
            ])
        }

        let firebaseConfig: AppConfigFile.FirebaseConfigDictionary? = try {
            guard let firebaseConfigFilePath else {
                return nil
            }
            if firebaseConfigFilePath == URL(argument: "<emulator>") {
                return .emulator
            }
            let data = try Data(contentsOf: firebaseConfigFilePath)
            return try PropertyListDecoder().decode(AppConfigFile.FirebaseConfigDictionary.self, from: data)
        }()
        let config = AppConfigFile(
            launchMode: launchMode,
            firebaseConfig: firebaseConfig
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(config)
        try data.write(to: outputUrl)
    }


    private func studyValue<V>(
        for studyId: Study.ID,
        in values: [StudyIdIdentified<V>],
        default defaultValue: @autoclosure () -> V
    ) -> V {
        _studyValue(for: studyId, in: values) ?? defaultValue()
    }
    
    private func studyValue<V>(
        for studyId: Study.ID,
        in values: [StudyIdIdentified<V>],
        default defaultValue: @autoclosure () -> V?
    ) -> V? {
        _studyValue(for: studyId, in: values) ?? defaultValue()
    }
    
    private func _studyValue<V>(for studyId: Study.ID, in values: [StudyIdIdentified<V>]) -> V? {
        values.last { $0.studyId == studyId }?.value ?? values.last(where: \.isWildcard)?.value
    }
}


// MARK: Utils

extension ExportConfigFile {
    struct StudyIdIdentified<Value: ExpressibleByArgument>: ExpressibleByArgument {
        let studyId: String
        let value: Value

        var isWildcard: Bool {
            studyId == "*"
        }

        init?(argument: String) {
            guard let idx = argument.firstIndex(of: ":") else {
                return nil
            }
            self.studyId = String(argument[..<idx])
            guard let value = Value(argument: String(argument[argument.index(after: idx)...])) else {
                return nil
            }
            self.value = value
        }
    }
}

extension Array {
    fileprivate func validate<V>(optionName: String) throws where Element == ExportConfigFile.StudyIdIdentified<V> {
        guard count(where: \.isWildcard) <= 1 else {
            throw NSError(domain: "edu.stanford.plainly.CLI", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Multiple wildcard entries in \(optionName). At most one is allowed!"
            ])
        }
    }
}

extension AppLaunchMode: ExpressibleByArgument {
    public static var allValueStrings: [String] {
        var allOptions = [Self.test, .study(studyId: nil)]
        for study in Study.allStudies {
            allOptions.append(.study(studyId: study.id))
        }
        return allOptions.map(\.rawValue)
    }
}


extension URL: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self = URL(filePath: argument, relativeTo: .currentDirectory())
    }
}
