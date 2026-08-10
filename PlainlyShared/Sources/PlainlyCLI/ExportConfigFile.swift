//
// This source file is part of the Plainly iOS open-source project
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
}


// MARK: Utils

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
