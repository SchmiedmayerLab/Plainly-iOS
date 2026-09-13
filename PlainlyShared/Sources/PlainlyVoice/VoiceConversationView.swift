//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


private struct VoicePhaseLabel: View {
    let phase: VoicePhase

    private var text: String {
        Self.text(for: phase)
    }

    var body: some View {
        ZStack {
            if phase.isFailure {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .modifier(GlassPill(tint: .red))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                Text(text)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    // Each state is its own view, so one dissolves as the next forms instead of the two overlapping.
                    .id(text)
                    .transition(.blurReplace)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 32)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: phase)
        .accessibilityAddTraits(.updatesFrequently)
    }

    static func text(for phase: VoicePhase) -> String {
        switch phase {
        case .idle:
            String(localized: "Voice is off", bundle: .module)
        case .connecting:
            String(localized: "Connecting…", bundle: .module)
        case .listening:
            String(localized: "Listening", bundle: .module)
        case .thinking:
            String(localized: "Thinking…", bundle: .module)
        case .speaking:
            String(localized: "Speaking", bundle: .module)
        case .muted:
            String(localized: "Muted", bundle: .module)
        case .paused:
            String(localized: "Paused. Tap the orb to resume.", bundle: .module)
        case .failed(let message):
            message
        }
    }
}


/// A floating capsule of glass, or of material where glass is not available.
private struct GlassPill: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.18)), in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}


private struct VoiceLineView: View {
    let line: VoiceLine
    let isCurrent: Bool

    var body: some View {
        Group {
            switch line.speaker {
            case .participant:
                Text(line.text)
                    .font(.callout)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .accessibilityLabel(Text("You said: \(line.text)", bundle: .module))
            case .assistant:
                Text(line.text)
                    .font(.body)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .accessibilityLabel(Text("Assistant: \(line.text)", bundle: .module))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// The running transcript: every line stays where it was said, new ones slide in from below and push the rest up
/// into the fade. It is not for reading back, so it does not scroll by touch, except at accessibility text sizes and
/// under VoiceOver, where the start of a long answer would otherwise be out of reach; the chat keeps the record.
private struct VoiceTranscriptView: View {
    let lines: [VoiceLine]
    let phase: VoicePhase

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    /// Only then do lines leave upward, and only then is there anything to fade.
    private var overflows: Bool {
        contentHeight > viewportHeight + 1
    }

    private var showsInvitation: Bool {
        phase == .listening && lines.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showsInvitation {
                        Text("Go ahead, I'm listening.", bundle: .module)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                    ForEach(lines) { line in
                        VoiceLineView(line: line, isCurrent: line.id == lines.last?.id)
                            .id(line.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                // Grows from the bottom: a short transcript sits low, near the control, rather than hanging under the orb.
                .frame(minHeight: viewportHeight, alignment: .bottom)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .defaultScrollAnchor(.bottom)
            .scrollDisabled(!dynamicTypeSize.isAccessibilitySize && !isVoiceOverEnabled)
            .scrollIndicators(.hidden)
            .mask {
                fade
                    .animation(.easeInOut(duration: 0.35), value: overflows)
            }
            .onChange(of: lines.last?.id) {
                follow(with: proxy)
            }
            .onChange(of: lines.last?.text.count) {
                follow(with: proxy)
            }
        }
        // New lines animate in; the growing last line does not, since it changes many times a second.
        .animation(.smooth(duration: 0.45), value: lines.map(\.id))
        .animation(.easeInOut(duration: 0.3), value: showsInvitation)
    }

    /// Older lines dissolve into the space under the orb instead of ending at a hard edge. Fully opaque until
    /// something actually leaves, so a short transcript is not dimmed for nothing.
    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(overflows ? 0 : 1), location: 0),
                .init(color: .black.opacity(overflows ? 0.06 : 1), location: 0.08),
                .init(color: .black.opacity(overflows ? 0.22 : 1), location: 0.17),
                .init(color: .black.opacity(overflows ? 0.5 : 1), location: 0.26),
                .init(color: .black.opacity(overflows ? 0.8 : 1), location: 0.34),
                .init(color: .black, location: 0.42),
                .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func follow(with proxy: ScrollViewProxy) {
        guard let last = lines.last?.id else {
            return
        }
        withAnimation(.smooth(duration: 0.45)) {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}


/// The orb doubles as the pause control: one tap holds the conversation, the next lets it go on.
private struct VoicePauseControl: View {
    let presenter: any VoicePresenter

    private var isPaused: Bool {
        presenter.phase == .paused
    }

    private var canPause: Bool {
        switch presenter.phase {
        case .listening, .thinking, .speaking, .paused:
            true
        default:
            false
        }
    }

    var body: some View {
        Button {
            presenter.isPaused.toggle()
        } label: {
            VoiceOrb(phase: presenter.phase, levels: presenter.levels)
                .overlay {
                    if isPaused {
                        VoicePauseBadge()
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canPause)
        .sensoryFeedback(.selection, trigger: isPaused)
        .animation(.spring(duration: 0.45, bounce: 0.35), value: isPaused)
        .accessibilityLabel(Text("Voice conversation", bundle: .module))
        .accessibilityValue(Text(VoicePhaseLabel.text(for: presenter.phase)))
        .accessibilityHint(Text(isPaused ? "Resumes the conversation." : "Pauses the conversation.", bundle: .module))
    }
}


/// The pause mark on a held orb: a small disc of glass with the glyph, so it reads as a state, not a button.
private struct VoicePauseBadge: View {
    var body: some View {
        Image(systemName: "pause.fill")
            .accessibilityHidden(true)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 84, height: 84)
            .modifier(GlassDisc())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}


private struct GlassDisc: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular.tint(.white.opacity(0.25)), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}


private struct VoiceMuteButton: View {
    let presenter: any VoicePresenter

    private var isMuted: Bool {
        presenter.isMuted
    }

    var body: some View {
        let button = Button {
            presenter.isMuted.toggle()
        } label: {
            Label(
                isMuted ? String(localized: "Unmute", bundle: .module) : String(localized: "Mute", bundle: .module),
                systemImage: isMuted ? "mic.slash.fill" : "mic.fill"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .disabled(presenter.phase == .idle || presenter.phase == .connecting || presenter.phase == .paused)
        if #available(iOS 26.0, macOS 26.0, *) {
            button
                .buttonStyle(.glass)
                .tint(isMuted ? Color.red : nil)
        } else {
            button
                .buttonStyle(.bordered)
                .tint(isMuted ? Color.red : Color.gray)
        }
    }
}


private struct VoiceRetryButton: View {
    let presenter: any VoicePresenter

    var body: some View {
        let button = Button {
            Task {
                await presenter.start()
            }
        } label: {
            Label(String(localized: "Try again", bundle: .module), systemImage: "arrow.clockwise")
        }
        if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }
}


/// The voice conversation as the participant sees it: the assistant's presence, what is being said, and the one control that matters.
///
/// Drop it where a chat would go; everything around it stays the host's.
public struct VoiceConversationView: View {
    private let presenter: any VoicePresenter

    @State private var hasAppeared = false

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            VoicePauseControl(presenter: presenter)
                .frame(width: 164, height: 164)
                // The orb's own motion must not become layout motion; without this the first frames animate it
                // in from the corner instead of letting it grow into place.
                .geometryGroup()
                .scaleEffect(hasAppeared ? 1 : 0.6)
                .opacity(hasAppeared ? 1 : 0)
                .padding(.bottom, 40)
            VoicePhaseLabel(phase: presenter.phase)
            Spacer(minLength: 16)
            VoiceTranscriptView(lines: presenter.transcript, phase: presenter.phase)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 300)
            controls
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .padding(.top, 28)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // The edge is the participant's: it lights only on their turn, never for what the assistant says.
            VoiceEdgeGlow(levels: presenter.levels, isActive: presenter.phase == .listening)
        }
        // Felt rather than seen, so eyes can stay off the screen.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: presenter.phase) { old, new in
            Self.nudges(from: old, to: new)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) {
                hasAppeared = true
            }
        }
    }

    @ViewBuilder private var controls: some View {
        ZStack {
            if presenter.phase.isFailure {
                VoiceRetryButton(presenter: presenter)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                VoiceMuteButton(presenter: presenter)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: presenter.phase.isFailure)
    }


    /// - Parameter presenter: The live ``VoiceConversation``, or a ``VoiceDemoPresenter``.
    public init(presenter: any VoicePresenter) {
        self.presenter = presenter
    }


    /// A nudge when the assistant takes the question and when it starts to answer; the pauses between its sentences
    /// stay quiet.
    private static func nudges(from old: VoicePhase, to new: VoicePhase) -> Bool {
        switch (old, new) {
        case (.listening, .thinking), (.thinking, .speaking):
            true
        default:
            false
        }
    }
}


#Preview("Conversation") {
    let demo = VoiceDemoPresenter()
    VoiceConversationView(presenter: demo)
        .task {
            await demo.start()
        }
}

#Preview("Thinking") {
    let demo = VoiceDemoPresenter(phase: .thinking)
    VoiceConversationView(presenter: demo)
        .task {
            await demo.start()
        }
}
