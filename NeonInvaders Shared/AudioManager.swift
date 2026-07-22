//
//  AudioManager.swift
//  NeonInvaders Shared
//
//  Procedurally-synthesised retro sound effects (no audio assets required).
//

import Foundation
import AVFoundation

final class AudioManager {

    static let shared = AudioManager()

    enum SoundID {
        case shoot
        case explosion
        case playerExplosion
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SoundID: AVAudioPCMBuffer] = [:]
    private var started = false
    private let sampleRate: Float = 44_100

    private init() {}

    /// Builds the sound buffers and starts the audio engine. Safe to call repeatedly.
    func start() {
        guard !started else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        buffers[.shoot]           = makeShoot()
        buffers[.explosion]       = makeExplosion(duration: 0.45, lowFreq: 95, noiseLevel: 1.0, amp: 0.34)
        buffers[.playerExplosion] = makeExplosion(duration: 0.70, lowFreq: 55, noiseLevel: 0.8, amp: 0.40)

        let mixer = engine.mainMixerNode
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: format)
            players.append(node)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            players.removeAll()
            return
        }
        players.forEach { $0.play() }
        started = true
    }

    /// Plays a sound effect. Round-robins across player nodes for polyphony.
    func play(_ id: SoundID) {
        guard started, let buffer = buffers[id], !players.isEmpty else { return }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Waveform synthesis

    private func makeBuffer(frames: Int) -> (AVAudioPCMBuffer, UnsafeMutablePointer<Float>) {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        return (buffer, buffer.floatChannelData![0])
    }

    /// Classic arcade "pew": a square wave sweeping downward with a fast decay.
    private func makeShoot() -> AVAudioPCMBuffer {
        let duration: Float = 0.14
        let n = Int(sampleRate * duration)
        let (buffer, ptr) = makeBuffer(frames: n)
        var phase: Float = 0
        for i in 0..<n {
            let prog = Float(i) / Float(n)
            let freq = 1000 - 700 * prog                 // 1000 Hz -> 300 Hz
            phase += 2 * .pi * freq / sampleRate
            let square: Float = sin(phase) >= 0 ? 1 : -1
            let env = expf(-prog * 6)                    // quick fade
            ptr[i] = square * env * 0.22
        }
        return buffer
    }

    /// "Boom": exponentially-decaying noise burst mixed with a low sine rumble.
    private func makeExplosion(duration: Float, lowFreq: Float, noiseLevel: Float, amp: Float) -> AVAudioPCMBuffer {
        let n = Int(sampleRate * duration)
        let (buffer, ptr) = makeBuffer(frames: n)
        for i in 0..<n {
            let prog = Float(i) / Float(n)
            let env = expf(-prog * 5)
            let noise = Float.random(in: -1...1) * noiseLevel
            let rumble = sin(2 * .pi * lowFreq * Float(i) / sampleRate)
            ptr[i] = (noise * 0.6 + rumble * 0.4) * env * amp
        }
        return buffer
    }
}
