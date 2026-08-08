//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import ArgumentParser
import Foundation


@main
struct PlainlyCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "PlainlyCLI",
        abstract: "Utility tools for the Plainly app",
        usage: nil,
        discussion: "",
        version: "0.0.1",
        shouldDisplay: true,
        subcommands: [
            ExportConfigFile.self,
            SimulateSession.self
        ],
        groupedSubcommands: [],
        defaultSubcommand: nil,
        helpNames: nil,
        aliases: []
    )
    
    func run() async throws {
        print(Self.helpMessage())
    }
}
