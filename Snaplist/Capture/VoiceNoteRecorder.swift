import AVFoundation
import SwiftUI

/// Record a note about where something is. Saved as audio and transcribed
/// on the iPhone, so "where did I put…" can find it.
struct VoiceNoteRecorder: View {
    var onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recorder: AVAudioRecorder?
    @State private var startedAt: Date?
    @State private var recordedSeconds: TimeInterval = 0
    @State private var message: String?
    @State private var fileURL = FileManager.default.temporaryDirectory
        .appending(path: "voice-note-\(UUID().uuidString).m4a")

    private var isRecording: Bool { recorder?.isRecording ?? false }
    private var hasRecording: Bool { !isRecording && recordedSeconds > 0.5 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Say what it is and where you put it.")
                        .font(Theme.display(.title2, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("“Spare HDMI cable, hall closet, top shelf.”")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)

                Spacer()

                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isRecording ? .primary : .secondary)
                }

                Button(action: toggle) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Theme.accent)
                            .frame(width: 92, height: 92)
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
                .sensoryFeedback(.impact, trigger: isRecording)

                Text(isRecording ? "Tap to stop" : hasRecording ? "Tap to record again" : "Tap to record")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stop()
                        try? FileManager.default.removeItem(at: fileURL)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(fileURL)
                        dismiss()
                    }
                    .disabled(!hasRecording)
                }
            }
        }
        .interactiveDismissDisabled(isRecording || hasRecording)
    }

    private var elapsed: TimeInterval {
        if let startedAt, isRecording { return Date.now.timeIntervalSince(startedAt) }
        return recordedSeconds
    }

    private func toggle() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            message = "Snaplist needs the microphone to record notes. You can allow it in Settings."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio)
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: fileURL, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            guard recorder.record() else {
                message = "Recording couldn't start."
                return
            }
            self.recorder = recorder
            startedAt = .now
            message = nil
        } catch {
            message = "Recording couldn't start: \(error.localizedDescription)"
        }
    }

    private func stop() {
        guard let recorder, recorder.isRecording else { return }
        recordedSeconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Plays a voice note, in the record's page viewer.
struct AudioNoteCard: View {
    let url: URL
    let transcript: String?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)

            if let transcript, !transcript.isEmpty {
                Text("“\(transcript)”")
                    .font(Theme.display(.title3, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .padding(.horizontal)
            }

            Button {
                toggle()
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if let player {
                Text(Duration.seconds(player.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .task { player = try? AVAudioPlayer(contentsOf: url) }
        .onDisappear { player?.stop() }
        .task(id: isPlaying) {
            // Notice when playback reaches the end.
            while isPlaying, let player {
                try? await Task.sleep(for: .milliseconds(250))
                if !player.isPlaying { isPlaying = false }
            }
        }
    }

    private func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
        }
    }
}
