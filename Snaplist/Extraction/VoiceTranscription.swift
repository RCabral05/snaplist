import Foundation
import Speech

/// Turns a voice note into text on the iPhone. Recognition is required to
/// run on-device: if this phone or language can't do that, the note is kept
/// and playable but not transcribed, rather than sent to a server.
enum VoiceTranscription {
    enum Failure: Error, LocalizedError {
        case notAllowed, unavailable, notOnDevice

        var errorDescription: String? {
            switch self {
            case .notAllowed: "Speech recognition is turned off for Snaplist. You can allow it in Settings."
            case .unavailable: "Speech recognition isn't available right now. Try again later."
            case .notOnDevice: "This iPhone can't transcribe this language on the device, so the note wasn't transcribed. It's still saved and playable."
            }
        }
    }

    static func transcribe(_ url: URL) async throws -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw Failure.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw Failure.unavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw Failure.notOnDevice }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.shouldReportPartialResults = false

        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.run { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    once.run { continuation.resume(throwing: error) }
                }
            }
        }
    }
}

/// The recognizer can report more than once; a continuation must resume once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
