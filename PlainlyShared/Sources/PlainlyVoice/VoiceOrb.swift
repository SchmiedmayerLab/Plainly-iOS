//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// The assistant's presence on the voice screen: a soft gradient body that breathes on its own, leans in while
/// the participant speaks, and swells with its own voice.
///
/// Motion is the signal. Colour carries the phase, loudness the scale, and nothing else moves, so the shape stays
/// calm enough to look at for a whole conversation.
public struct VoiceOrb: View {
    /// The body is the app's accent colour and nothing else; the phase shows in how the halo around it is lit,
    /// lighter or deeper shades of the same colour, and in how the surface moves.
    struct Palette {
        let body: [Color]
        let glow: Color
        let glowOpacity: Double
        /// Relative speed of the surface motion; thinking hurries, resting barely stirs.
        let drift: Double

        init(accent: Color, glow: Color, glowOpacity: Double, drift: Double) {
            let light = accent.mix(with: .white, by: 0.45)
            let deep = accent.mix(with: .black, by: 0.25)
            body = [
                light, light, accent,
                light, accent, deep,
                accent, deep, deep
            ]
            self.glow = glow
            self.glowOpacity = glowOpacity
            self.drift = drift
        }

        /// The colour the body is painted in: the accent, or a quiet grey while the conversation is held.
        static func base(for phase: VoicePhase, accent: Color) -> Color {
            switch phase {
            case .muted, .paused:
                Color(white: 0.72)
            default:
                accent
            }
        }

        static func palette(for phase: VoicePhase, accent: Color) -> Palette {
            let base = base(for: phase, accent: accent)
            return switch phase {
            case .idle, .connecting:
                Palette(accent: base, glow: accent.mix(with: .white, by: 0.6), glowOpacity: 0.12, drift: 0.5)
            case .listening:
                Palette(accent: base, glow: accent.mix(with: .white, by: 0.4), glowOpacity: 0.28, drift: 1)
            case .thinking:
                Palette(accent: base, glow: accent.mix(with: .black, by: 0.2), glowOpacity: 0.32, drift: 2.4)
            case .speaking:
                Palette(accent: base, glow: accent, glowOpacity: 0.4, drift: 1.4)
            case .muted, .paused:
                Palette(accent: base, glow: Color(white: 0.7), glowOpacity: 0.12, drift: 0.3)
            case .failed:
                Palette(accent: base, glow: accent.mix(with: .black, by: 0.5), glowOpacity: 0.25, drift: 0.3)
            }
        }
    }

    private let phase: VoicePhase
    private let levels: VoiceAudioLevels

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The orb is the assistant: it moves with its own voice, and only hints at the participant's, whose voice the
    // screen edge answers instead.
    private var level: Float {
        switch phase {
        case .speaking:
            min(levels.output * 1.2, 1)
        case .listening:
            levels.input * 0.25
        default:
            0
        }
    }

    private var palette: Palette {
        Palette.palette(for: phase, accent: .accentColor)
    }

    private var isLive: Bool {
        switch phase {
        case .connecting, .listening, .thinking, .speaking:
            true
        case .idle, .muted, .paused, .failed:
            false
        }
    }

    public var body: some View {
        let palette = palette
        // A resting orb has nothing to follow, so its timeline stops instead of redrawing a still picture.
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isLive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * palette.drift
            ZStack {
                Circle()
                    .fill(palette.glow)
                    .blur(radius: 26)
                    .scaleEffect(1 + CGFloat(level) * 0.45)
                    .opacity(palette.glowOpacity)
                MeshGradient(width: 3, height: 3, points: meshPoints(at: time), colors: palette.body)
                    .overlay { light(at: time) }
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
                    .shadow(color: palette.glow.opacity(0.35), radius: 16, y: 8)
            }
            .scaleEffect(1 + CGFloat(level) * 0.18)
            // Thinking breathes slowly on its own, so a long wait still looks like work.
            .scaleEffect(phase == .thinking ? 1 + 0.05 * sin(timeline.date.timeIntervalSinceReferenceDate * 2.6) : 1)
        }
        .animation(.smooth(duration: 0.22), value: level)
        .animation(.easeInOut(duration: 0.6), value: phase)
        .accessibilityHidden(true)
    }


    /// - Parameters:
    ///   - phase: Sets the colour and the pace of the surface.
    ///   - levels: Whichever side is speaking sets the size.
    public init(phase: VoicePhase, levels: VoiceAudioLevels) {
        self.phase = phase
        self.levels = levels
    }


    /// A soft light that travels slowly across the body, so the surface keeps changing in the accent's own shades.
    private func light(at time: Double) -> some View {
        let center = UnitPoint(x: 0.5 + 0.35 * sin(time * 0.35), y: 0.5 + 0.35 * cos(time * 0.27 + 1))
        return ZStack {
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: center, startRadius: 0, endRadius: 120)
            RadialGradient(
                colors: [.black.opacity(0.2), .clear],
                center: UnitPoint(x: 1 - center.x, y: 1 - center.y),
                startRadius: 0,
                endRadius: 130
            )
        }
    }

    /// The centre control point wanders on two slow, unrelated circles, so the surface never repeats; the rim stays
    /// put, since a rim point that moves inward leaves part of the circle unpainted.
    private func meshPoints(at time: Double) -> [SIMD2<Float>] {
        let centre = SIMD2<Float>(
            0.5 + 0.2 * Float(sin(time * 0.9)) + 0.08 * Float(sin(time * 2.3 + 1)),
            0.5 + 0.2 * Float(cos(time * 0.7 + 2)) + 0.08 * Float(cos(time * 1.9))
        )
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], centre, [1, 0.5],
            [0, 1], [0.5, 1], [1, 1]
        ]
    }
}


#Preview("Listening") {
    VoiceOrb(phase: .listening, levels: VoiceAudioLevels())
        .frame(width: 200, height: 200)
}
