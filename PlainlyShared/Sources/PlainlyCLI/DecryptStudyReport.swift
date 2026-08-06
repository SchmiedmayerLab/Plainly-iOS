//
// This source file is part of the Stanford Spezi project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//


import ArgumentParser
import CryptoKit
import Foundation
import PlainlyShared
import PlainlyStudyDefinitions


struct DecryptStudyReport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decrypt-study-report",
        abstract: "Decrypts a study report file encrypted by the Plainly app",
    )

    @Option(name: .short, help: "The private_key.pem file") var keyUrl: URL

    @Argument(help: "Input file") var inputUrl: URL

    @Argument(help: "Output file. ('-' for stdout)") var outputUrl: URL

    func run() throws {
        let key = try Curve25519.KeyAgreement.PrivateKey(contentsOf: keyUrl)
        let input = try Data(contentsOf: inputUrl)
        let decrypted = try input.decrypted(using: key)
        if outputUrl == URL(argument: "-") {
            let string = String(decoding: decrypted, as: UTF8.self)
            print(string)
        } else {
            try decrypted.write(to: outputUrl)
        }
    }
}
