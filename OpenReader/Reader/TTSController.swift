import AVFoundation
import Foundation
import UIKit

/// 语音朗读控制器（系统 TTS）。
/// 刻意不挂 @MainActor，避免 AVSpeechSynthesizerDelegate 的隔离冲突，
/// 回调统一回到主线程。
final class TTSController: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    var onFinished: (() -> Void)?
    var onStateChanged: ((Bool) -> Void)?

    private(set) var isActive = false {
        didSet {
            if oldValue != isActive {
                onStateChanged?(isActive)
            }
        }
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, rate: Float, pitch: Float) {
        configureAudioSession()
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.05
        if let voice = AVSpeechSynthesisVoice(language: "zh-CN") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
        isActive = true
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    var isPaused: Bool { synthesizer.isPaused }
    var isSpeaking: Bool { synthesizer.isSpeaking && !synthesizer.isPaused }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            NSLog("OpenReader: 音频会话配置失败 %@", error.localizedDescription)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isActive = false
            self.onFinished?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isActive = false
        }
    }
}
