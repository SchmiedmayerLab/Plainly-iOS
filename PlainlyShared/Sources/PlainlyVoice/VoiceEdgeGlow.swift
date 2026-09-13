//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Light at the screen edge that follows the participant's voice, so speaking is acknowledged before any words are.
///
/// The light is brightest exactly on the edge and fades inward. Two rings of the accent's shades drift along the
/// rim in opposite directions, so the brightness moves along the border without the border itself ever moving.
public struct VoiceEdgeGlow: View {
    // Room tone and the assistant's own voice leaking into the microphone stay below this.
    private static let noiseFloor: Float = 0.12

    private let levels: VoiceAudioLevels
    private let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Read here rather than by the screen, so a new level redraws the glow and nothing else.
    private var level: Float {
        levels.input
    }

    private var strength: Double {
        isActive ? Double(min(max(level - Self.noiseFloor, 0) * 2.5, 1)) : 0
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || strength == 0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ring(shades: Self.shades(of: .accentColor), angle: time / 70, width: 16 + strength * 10, blur: 18)
                ring(shades: Self.shades(of: .accentColor).reversed(), angle: -time / 110, width: 8 + strength * 6, blur: 24)
                    .opacity(0.5)
            }
        }
        .opacity(0.35 + strength * 0.45)
        .opacity(isActive && strength > 0 ? 1 : 0)
        // Slow to follow the voice on purpose: the light should change, not flicker with every syllable.
        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: level)
        .animation(.easeOut(duration: 0.5), value: isActive)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }


    /// - Parameters:
    ///   - levels: The live levels; the participant's loudness sets the strength.
    ///   - isActive: Whether the glow may show at all, typically only while listening.
    public init(levels: VoiceAudioLevels, isActive: Bool) {
        self.levels = levels
        self.isActive = isActive
    }


    /// The accent and its lighter and deeper selves, closed into a ring.
    private static func shades(of accent: Color) -> [Color] {
        let light = accent.mix(with: .white, by: 0.5)
        let deep = accent.mix(with: .black, by: 0.3)
        return [accent, light, accent, deep, accent, light, deep, accent]
    }

    /// A stroke centred on the screen edge, so half of it lies off-screen and its peak sits right on the border.
    private func ring(shades: [Color], angle: Double, width: Double, blur: Double) -> some View {
        RoundedRectangle(cornerRadius: 56, style: .continuous)
            .stroke(
                AngularGradient(colors: shades, center: .center, angle: .degrees(angle * 360)),
                lineWidth: width
            )
            .padding(-width / 2)
            .blur(radius: blur)
    }
}
