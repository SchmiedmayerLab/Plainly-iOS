//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import FirebaseCore
import GeneratedOpenAIClient // periphery:ignore - false positive
import PlainlyShared
@_spi(APISupport) import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziFirebaseConfiguration
import SpeziFirebaseStorage
import SpeziFoundation
import SpeziHealthKit
import SpeziKeychainStorage
import SpeziLLM
import SpeziLLMOpenAI


final class PlainlyDelegate: SpeziAppDelegate {
    /// The Firebase emulators bind to IPv4, while `localhost` resolves to `::1` first in the simulator,
    /// so the emulator hosts have to be addressed by their IPv4 address.
    private static let emulatorHost = "127.0.0.1"

    override var configuration: Configuration {
        Configuration(standard: PlainlyStandard()) {
            if !FeatureFlags.disableFirebase, let config = firebaseConfig {
                firebaseModules(using: config)
            }
            let chatInterceptor = FirebaseChatInterceptor()
            chatInterceptor
            FHIRInterpretationModule()
            HealthKit {
                if !FeatureFlags.disableHealthRecords, HKHealthStore().supportsHealthRecords() {
                    RequestReadAccess(other: PlainlyStandard.recordTypes)
                    for type in PlainlyStandard.recordTypes {
                        CollectSamples(type, start: .manual, continueInBackground: false, timeRange: .newSamples)
                    }
                }
            }
            LLMRunner {
                // `chatInterceptor` reroutes every request to the Firebase chat function, which holds
                // the inference credentials, so the platform itself never authenticates.
                LLMOpenAIPlatform(configuration: .init(
                    authToken: .none,
                    concurrentStreams: 100,
                    retryPolicy: .attempts(3),
                    middlewares: [chatInterceptor]
                ))
            }
        }
    }

    private var firebaseConfig: AppConfigFile.FirebaseConfigDictionary? {
        let config = FeatureFlags.useFirebaseEmulator ? .emulator : AppConfigFile.current().firebaseConfig
        guard let config else {
            AppDiagnostics.configuration.fault("Firebase configuration is unavailable")
            return nil
        }
        let missingKeys = config.missingRequiredKeys
        guard missingKeys.isEmpty else {
            AppDiagnostics.configuration.fault(
                "Firebase configuration contains missing or invalid required keys: \(missingKeys.joined(separator: ","), privacy: .public)"
            )
            return nil
        }
        return config
    }
    
    private var accountEmulatorSettings: (host: String, port: Int)? {
        if FeatureFlags.useFirebaseEmulator {
            (host: Self.emulatorHost, port: 9099)
        } else {
            nil
        }
    }


    @ModuleBuilder
    private func firebaseModules(using config: AppConfigFile.FirebaseConfigDictionary) -> ModuleCollection {
        let options = firebaseOptions(using: config)
        ConfigureFirebaseApp(options: options)
        AccountConfiguration(
            service: FirebaseAccountService(
                providers: [],
                emulatorSettings: accountEmulatorSettings
            ),
            configuration: []
        )
        if FeatureFlags.useFirebaseEmulator {
            FirebaseStorageConfiguration(emulatorSettings: (host: Self.emulatorHost, port: 9199))
            FirebaseFunctions(emulatorHost: Self.emulatorHost, port: 5001)
        } else {
            FirebaseStorageConfiguration()
            FirebaseFunctions()
        }
        FirebaseUpload()
        PendingReportStore()
    }

    private func firebaseOptions(using config: AppConfigFile.FirebaseConfigDictionary) -> FirebaseOptions {
        guard let options = FirebaseOptions(config) else {
            AppDiagnostics.configuration.fault("FirebaseOptions could not be created from the configured keys")
            preconditionFailure("Invalid Firebase configuration")
        }
        return options
    }
}


extension FirebaseOptions {
    convenience init?(_ config: AppConfigFile.FirebaseConfigDictionary) {
        let fileManager = FileManager.default
        let tmpUrl = URL.temporaryDirectory.appendingPathComponent("FirebaseConfig", conformingTo: .propertyList)
        try? fileManager.removeItem(at: tmpUrl)
        do {
            try config.asNSDictionary().write(to: tmpUrl)
        } catch {
            AppDiagnostics.configuration.logError(error, context: "Writing temporary Firebase configuration")
            return nil
        }
        defer {
            try? fileManager.removeItem(at: tmpUrl)
        }
        self.init(contentsOfFile: tmpUrl.absoluteURL.path(percentEncoded: false))
    }
}
