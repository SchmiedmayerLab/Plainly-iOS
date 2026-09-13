//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import AVFoundation
import Foundation
import os


enum VoiceAudioError: LocalizedError {
    case unsupportedFormat
    case interrupted

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            String(localized: "The device does not support the audio format the voice session needs.", bundle: .module)
        case .interrupted:
            String(localized: "The voice conversation was interrupted. Try again when you are ready.", bundle: .module)
        }
    }
}


/// Turns audio buffers into a perceptual loudness, no more often than a view can use it.
private final class LevelMeter: Sendable {
    private static let reportInterval: TimeInterval = 0.04
    // Speech peaks well below full scale, so the gain lifts a normal voice toward the top of the range.
    private static let gain: Float = 4

    private let lastReport = OSAllocatedUnfairLock(initialState: Date.distantPast)


    func level(of buffer: AVAudioPCMBuffer) -> Float? {
        let now = Date.now
        let due = lastReport.withLock { last in
            guard now.timeIntervalSince(last) >= Self.reportInterval else {
                return false
            }
            last = now
            return true
        }
        guard due else {
            return nil
        }
        return min(1, sqrt(rms(of: buffer)) * Self.gain)
    }

    private func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else {
            return 0
        }
        if let samples = buffer.floatChannelData?.pointee {
            var sum: Float = 0
            for index in 0..<frames {
                sum += samples[index] * samples[index]
            }
            return sqrt(sum / Float(frames))
        }
        if let samples = buffer.int16ChannelData?.pointee {
            var sum: Float = 0
            for index in 0..<frames {
                let sample = Float(samples[index]) / Float(Int16.max)
                sum += sample * sample
            }
            return sqrt(sum / Float(frames))
        }
        return 0
    }
}


/// Captures the microphone as the PCM16 24 kHz mono stream the Realtime API takes and plays what it sends back.
///
/// One engine carries both directions so the voice-processing input cancels the assistant's own voice.
/// Both directions report their loudness to ``VoiceAudioLevels`` for the screen to react to.
final class VoiceAudioEngine: @unchecked Sendable {
    /// The formats and converters the taps and playback work with, replaced as one when the route changes.
    private struct Conversion {
        let outputFormat: AVAudioFormat
        let output: AVAudioConverter?
        let input: AVAudioConverter?
    }

    private static let sampleRate = 24_000.0
    // Without echo cancellation the assistant hears itself; the microphone is held while it speaks and shortly after.
    private static let outputHold: TimeInterval = 1.0
    private static let outputHoldThreshold: Float = 0.03

    let microphone: AsyncStream<Data>

    /// While paused the microphone keeps running, so resuming is instant, but nothing is forwarded.
    var isPaused: Bool {
        get { paused.withLock { $0 } }
        set { paused.withLock { $0 = newValue } }
    }

    /// Like pause for the microphone alone; playback goes on.
    var isMuted: Bool {
        get { muted.withLock { $0 } }
        set { muted.withLock { $0 = newValue } }
    }

    /// Whether an answer is on its way; the microphone stays closed until it has been heard, so one question is
    /// answered at a time instead of a second one queuing up behind the first.
    var isAnswering: Bool {
        get { answering.withLock { $0 } }
        set { answering.withLock { $0 = newValue } }
    }

    private var isHoldingMicrophone: Bool {
        Date.now.timeIntervalSince(lastOutputActivity.withLock { $0 }) < Self.outputHold
    }

    private var outputSampleRate: Double {
        conversion.withLockUnchecked { $0?.outputFormat.sampleRate } ?? Self.sampleRate
    }

    /// How much of the assistant's audio has been queued since the queue was last emptied.
    var scheduledSeconds: TimeInterval {
        TimeInterval(scheduledFrames.withLock { $0 }) / outputSampleRate
    }

    /// How much of the assistant's audio has been heard; a caption tied to this position stays in step with the voice.
    var playedSeconds: TimeInterval {
        scheduledSeconds - queuedSeconds
    }

    /// How much of the assistant's audio has been queued but not heard yet.
    var queuedSeconds: TimeInterval {
        let scheduled = scheduledFrames.withLock { $0 }
        guard let nodeTime = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        let pending = scheduled - playerTime.sampleTime
        return pending > 0 ? TimeInterval(pending) / outputSampleRate : 0
    }

    private let continuation: AsyncStream<Data>.Continuation
    private let levels: VoiceAudioLevels
    private let inputMeter = LevelMeter()
    private let outputMeter = LevelMeter()
    private let paused = OSAllocatedUnfairLock(initialState: false)
    private let scheduledFrames = OSAllocatedUnfairLock(initialState: AVAudioFramePosition(0))
    private let muted = OSAllocatedUnfairLock(initialState: false)
    private let answering = OSAllocatedUnfairLock(initialState: false)
    private let lastOutputActivity = OSAllocatedUnfairLock(initialState: Date.distantPast)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pcmFormat: AVAudioFormat
    private let conversion = OSAllocatedUnfairLock<Conversion?>(uncheckedState: nil)
    // Rebuilding the graph after a route change and tearing it down on stop happen one at a time.
    private let graphLock = NSRecursiveLock()
    private var observers: [any NSObjectProtocol] = []
    /// Called when the engine cannot go on, e.g. after a route change it could not recover from.
    var onFailure: (@Sendable (any Error) -> Void)?


    init(levels: VoiceAudioLevels) throws {
        guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: false) else {
            throw VoiceAudioError.unsupportedFormat
        }
        self.pcmFormat = pcmFormat
        self.levels = levels
        (microphone, continuation) = AsyncStream.makeStream(of: Data.self)

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif

        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            throw error
        }
        engine.attach(player)
        connectGraph()
        engine.prepare()
        observeAudioEnvironment()
    }


    func start() throws {
        try engine.start()
        if !isPaused {
            player.play()
        }
    }

    func stop() {
        graphLock.lock()
        defer {
            graphLock.unlock()
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        player.removeTap(onBus: 0)
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Holds the assistant's audio where it is; ``resumePlayback()`` continues from there.
    func pausePlayback() {
        player.pause()
    }

    func resumePlayback() {
        player.play()
    }

    /// Queues one chunk of the assistant's PCM16 audio for playback.
    func play(_ pcm16: Data) {
        let frames = AVAudioFrameCount(pcm16.count / MemoryLayout<Int16>.size)
        guard frames > 0, let source = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frames) else {
            return
        }
        source.frameLength = frames
        pcm16.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress, let channel = source.int16ChannelData?.pointee {
                channel.update(from: base.assumingMemoryBound(to: Int16.self), count: Int(frames))
            }
        }
        guard let current = conversion.withLockUnchecked({ $0 }),
              let converted = convert(source, with: current.output, to: current.outputFormat) else {
            return
        }
        scheduledFrames.withLock { $0 += AVAudioFramePosition(converted.frameLength) }
        player.scheduleBuffer(converted)
    }

    /// A new route, such as headphones, or an interruption, such as a call, stops the engine; it is brought back
    /// once the system lets it, or the failure is reported.
    private func observeAudioEnvironment() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.restart()
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            self?.handleInterruption(note)
        })
        #endif
    }

    #if os(iOS)
    private func handleInterruption(_ note: Notification) {
        let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
        let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        switch type {
        case .began:
            Task { @MainActor [levels] in levels.reset() }
        case .ended where options.contains(.shouldResume):
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                restart()
            } catch {
                onFailure?(error)
            }
        case .ended:
            // The system does not hand the audio back yet; the participant starts again when they are ready.
            onFailure?(VoiceAudioError.interrupted)
        default:
            break
        }
    }
    #endif

    private func restart() {
        graphLock.lock()
        defer {
            graphLock.unlock()
        }
        do {
            // A new route can come with new hardware formats: the graph is wired again for them, and audio already
            // converted for the old ones is dropped.
            player.stop()
            scheduledFrames.withLock { $0 = 0 }
            connectGraph()
            try engine.start()
            if !isPaused {
                player.play()
            }
        } catch {
            onFailure?(error)
        }
    }

    /// Wires the player and both taps for the hardware formats in effect now.
    private func connectGraph() {
        let input = engine.inputNode
        player.removeTap(onBus: 0)
        input.removeTap(onBus: 0)
        engine.disconnectNodeOutput(player)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        // Swapped as one, so playback and capture never pair a new format with an old converter.
        let conversion = Conversion(
            outputFormat: outputFormat,
            output: AVAudioConverter(from: pcmFormat, to: outputFormat),
            input: AVAudioConverter(from: inputFormat, to: pcmFormat)
        )
        self.conversion.withLockUnchecked { $0 = conversion }
        player.installTap(onBus: 0, bufferSize: 1_024, format: outputFormat) { [weak self] buffer, _ in
            self?.meterOutput(buffer)
        }
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            self?.capture(buffer)
        }
    }

    private func capture(_ buffer: AVAudioPCMBuffer) {
        if let level = inputMeter.level(of: buffer) {
            Task { @MainActor [levels] in levels.update(input: level) }
        }
        guard !isPaused,
              let converted = convert(buffer, with: conversion.withLockUnchecked({ $0?.input }), to: pcmFormat),
              let channel = converted.int16ChannelData?.pointee else {
            return
        }
        let count = Int(converted.frameLength) * MemoryLayout<Int16>.size
        // Silence rather than nothing: the server's turn detection keeps hearing time pass, so a turn cut off by a
        // mute still ends and is answered, and the conversation goes on. Only a pause goes quiet on the wire.
        if isMuted || isAnswering || isHoldingMicrophone {
            continuation.yield(Data(count: count))
        } else {
            continuation.yield(Data(bytes: channel, count: count))
        }
    }

    private func meterOutput(_ buffer: AVAudioPCMBuffer) {
        guard let level = outputMeter.level(of: buffer) else {
            return
        }
        if level > Self.outputHoldThreshold {
            lastOutputActivity.withLock { $0 = .now }
        }
        Task { @MainActor [levels] in levels.update(output: level) }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else {
            return nil
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else {
            return nil
        }
        return output
    }
}
