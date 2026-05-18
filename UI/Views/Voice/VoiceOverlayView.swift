import SwiftUI

struct VoiceOverlayView: View {
    @ObservedObject var viewModel: VoiceOverlayViewModel
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @AppStorage(VoiceOverlayDefaults.customWords, store: UserDefaults(suiteName: VoiceOverlayDefaults.suiteName) ?? .standard)
    private var customWordsText = SettingsDefaults.voiceCustomWordsRaw

    @FocusState private var isTranscriptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            transcriptEditor
            customWordsSection
            historySection
            footer
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 360, alignment: .topLeading)
        .onAppear {
            if !viewModel.isDraftActive {
                viewModel.startDraftSession()
            }
            isTranscriptFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Voice")
                    .font(.headline)
                Text(viewModel.isDraftActive ? "Draft transcript" : "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Open Voice Settings")

            Button {
                viewModel.cancel()
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Cancel")
        }
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: Binding(
                get: { viewModel.transcript },
                set: { viewModel.updateTranscript($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .focused($isTranscriptFocused)
            .padding(8)
            .frame(minHeight: 130)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var customWordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Custom Words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply") {
                    viewModel.customWordsText = customWordsText
                    viewModel.applyCustomWords()
                }
                .disabled(customWordsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $customWordsText)
                .font(.caption)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 62, maxHeight: 78)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("History")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.history.prefix(3)) { item in
                    Button {
                        viewModel.updateTranscript(item.transcript)
                    } label: {
                        HStack {
                            Text(item.transcript)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Image(systemName: "arrow.uturn.left")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                viewModel.cancel()
                onClose()
            }

            Button("Copy") {
                viewModel.copyTranscriptToClipboard()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!viewModel.canCopyTranscript)
        }
    }
}

#if DEBUG
struct VoiceOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceOverlayView(viewModel: VoiceOverlayViewModel())
    }
}
#endif
