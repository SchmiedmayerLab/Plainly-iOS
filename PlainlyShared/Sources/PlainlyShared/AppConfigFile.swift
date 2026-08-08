//
// This source file is part of the Plainly iOS project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
private import OSLog
private import SpeziFoundation


/// The `UserStudyConfig.plist` file bundled with the app/
public struct AppConfigFile: Codable {
    private static let logger = Logger(subsystem: "edu.stanford.llmonfhir", category: "Configuration")

    /// The app's intended launch mode.
    public let appLaunchMode: AppLaunchMode
    /// The studies bundled with the app.
    public let studyConfigs: [Study.ID: StudyConfig]
    /// The firebase config the app should use, if any.
    public var firebaseConfig: FirebaseConfigDictionary?
    
    public init(launchMode: AppLaunchMode, studyConfigs: [Study.ID: StudyConfig], firebaseConfig: FirebaseConfigDictionary?) {
        self.appLaunchMode = launchMode
        self.studyConfigs = studyConfigs
        self.firebaseConfig = firebaseConfig
    }
}


extension AppConfigFile {
    /// Attempts to load a configuration from a plist file in the main bundle.
    public init?(nameInBundle: String) {
        guard let url = Bundle.main.url(forResource: nameInBundle, withExtension: "plist") else {
            Self.logger.fault("Configuration resource is missing; resource=\(nameInBundle, privacy: .public)")
            return nil
        }
        Self.logger.notice("Configuration resource found; resource=\(nameInBundle, privacy: .public)")
        self.init(contentsOf: url)
    }
    
    /// Attempts to load a configuration from a URL.
    public init?(contentsOf url: URL) {
        do {
            var data = try Data(contentsOf: url)
            do {
                self = try PropertyListDecoder().decode(Self.self, from: data)
            } catch {
                // if the decoding failed, its bc the file might be compressed
                data = try data.decompressed(using: Zstd.self)
                self = try PropertyListDecoder().decode(Self.self, from: data)
            }
        } catch {
            let nsError = error as NSError
            let typeName = String(reflecting: type(of: error))
            Self.logger.error("""
                Configuration decoding failed; file=\(url.lastPathComponent, privacy: .public); \
                type=\(typeName, privacy: .public); domain=\(nsError.domain, privacy: .public); code=\(nsError.code)
                """)
            return nil
        }
    }
    
    /// The configuration bundled with the app.
    ///
    /// Returns an empty ``Plainly/Plainly/Mode/standalone`` config if the file is not present or cannot be decoded.
    public static func current() -> Self {
        guard let configuration = Self(nameInBundle: "UserStudyConfig") else {
            logger.fault("Using empty standalone configuration fallback")
            return Self(launchMode: .standalone, studyConfigs: [:], firebaseConfig: nil)
        }
        logger.notice("""
            Configuration loaded; studyCount=\(configuration.studyConfigs.count); \
            hasFirebaseConfiguration=\(configuration.firebaseConfig != nil)
            """)
        return configuration
    }
}


extension AppConfigFile {
    public struct FirebaseConfigDictionary: Codable, Sendable {
        private enum Value: Codable, ExpressibleByBooleanLiteral, ExpressibleByStringLiteral, Sendable {
            case bool(Bool)
            case string(String)
            
            var anyValue: Any {
                switch self {
                case .bool(let value):
                    value
                case .string(let value):
                    value
                }
            }
            
            init(booleanLiteral value: Bool) {
                self = .bool(value)
            }
            
            init(stringLiteral value: String) {
                self = .string(value)
            }
            
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .string(value)
                } else if let value = try? container.decode(Bool.self) {
                    self = .bool(value)
                } else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))
                }
            }
            
            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .bool(let value):
                    try container.encode(value)
                case .string(let value):
                    try container.encode(value)
                }
            }
        }
        
        private let entries: [String: Value]

        /// Names of required Firebase configuration entries that are absent.
        public var missingRequiredKeys: [String] {
            let requiredKeys = [
                "API_KEY",
                "BUNDLE_ID",
                "GCM_SENDER_ID",
                "GOOGLE_APP_ID",
                "PLIST_VERSION",
                "PROJECT_ID",
                "STORAGE_BUCKET"
            ]
            return requiredKeys.filter { entries[$0] == nil }
        }
        
        private init(entries: [String: Value]) {
            self.entries = entries
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            entries = try container.decode([String: Value].self)
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(entries)
        }
        
        // swiftlint:disable legacy_objc_type
        public func asNSDictionary() -> NSDictionary {
            NSDictionary(dictionary: entries.mapValues(\.anyValue))
        }

        // swiftlint:enable legacy_objc_type
    }
}


extension AppConfigFile.FirebaseConfigDictionary {
    /// A firebase config that is suitable for connecting to the emulator.
    public static let emulator = Self(entries: [
        "API_KEY": "A00000000000000000000000000000000000000",
        "GCM_SENDER_ID": "GCM_SENDER_ID",
        "PLIST_VERSION": "1",
        "BUNDLE_ID": "edu.stanford.llmonfhir",
        "PROJECT_ID": "demo-plainly",
        "STORAGE_BUCKET": "demo-plainly.firebasestorage.app",
        "IS_ADS_ENABLED": false,
        "IS_ANALYTICS_ENABLED": false,
        "IS_APPINVITE_ENABLED": true,
        "IS_GCM_ENABLED": true,
        "IS_SIGNIN_ENABLED": true,
        "GOOGLE_APP_ID": "1:123456789012:ios:1234567890123456789012"
    ])
}
