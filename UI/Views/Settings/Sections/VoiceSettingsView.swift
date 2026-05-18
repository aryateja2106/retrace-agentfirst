import SwiftUI
import Shared

extension SettingsView {
    var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            voiceActivationCard
            voiceOutputCard
            voiceVocabularyCard
            voiceModelCard
        }
    }

    var voiceActivationCard: some View {
        ModernSettingsCard(title: "Voice Activation", icon: "waveform") {
            VStack(alignment: .leading, spacing: 16) {
                ModernToggleRow(
                    title: "Enable voice input",
                    subtitle: "Enables the local overlay workflow. Press the shortcut once to start and again to copy.",
                    isOn: $voiceEnabled
                )

                VStack(alignment: .leading, spacing: 8) {
                    settingsFieldLabel("Toggle mode")
                    ModernSegmentedPicker(selection: $voiceToggleMode, options: VoiceToggleMode.allCases) { mode in
                        VStack(spacing: 3) {
                            Text(mode.rawValue)
                            Text(mode.description)
                                .font(.retraceTiny)
                                .foregroundColor(.retraceSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                settingsShortcutRecorderRow(
                    label: "Voice overlay shortcut",
                    kind: .voice,
                    shortcut: $voiceShortcut,
                    isRecording: $isRecordingVoiceShortcut,
                    otherShortcuts: [timelineShortcut, dashboardShortcut, recordingShortcut, systemMonitorShortcut, commentShortcut]
                )

                Button {
                    VoiceOverlayWindowController.shared.show(source: "settings_voice_tab")
                } label: {
                    Label("Start Floating Draft", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            if voiceToggleMode != .toggle {
                voiceToggleMode = .toggle
            }
        }
    }

    var voiceOutputCard: some View {
        ModernSettingsCard(title: "Output", icon: "doc.on.clipboard") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsFieldLabel("Output mode")
                    ModernSegmentedPicker(selection: $voiceOutputMode, options: VoiceOutputMode.allCases) { mode in
                        VStack(spacing: 3) {
                            Text(mode.rawValue)
                            Text(mode.description)
                                .font(.retraceTiny)
                                .foregroundColor(.retraceSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                ModernToggleRow(
                    title: "Show floating overlay",
                    subtitle: "Use an editable floating transcript panel before copying text to agents or other apps.",
                    isOn: $voiceShowFloatingOverlay
                )

                Stepper(
                    "History limit: \(voiceHistoryLimit) items",
                    value: $voiceHistoryLimit,
                    in: 0...200,
                    step: 5
                )
                .font(.retraceCaption)
                .foregroundColor(.retraceSecondary)
            }
        }
    }

    var voiceVocabularyCard: some View {
        ModernSettingsCard(title: "Custom Words", icon: "text.quote") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Corrections for names and project terms. Use lines like cloud AI => Claude AI or research AI => LeSearch AI.")
                    .font(.retraceCaption)
                    .foregroundColor(.retraceSecondary)

                TextEditor(text: $voiceCustomWordsRaw)
                    .font(.retraceMono)
                    .foregroundColor(.retracePrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 110)
                    .background(Color.retraceControlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.retraceHairline, lineWidth: 1)
                    )
            }
        }
    }

    var voiceModelCard: some View {
        ModernSettingsCard(title: "Model Lifecycle", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 14) {
                ModernToggleRow(
                    title: "Unload model after idle",
                    subtitle: "Prefer freeing memory when voice input has been inactive.",
                    isOn: $voiceUnloadModelAfterIdle
                )

                Text("Current build: overlay and correction workflow only. Planned STT target: MLX Parakeet V3 or the smallest reliable Apple Silicon model that does not stay resident all day.")
                    .font(.retraceCaption)
                    .foregroundColor(.retraceSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsFieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.retraceCaptionMedium)
            .foregroundColor(.retraceSecondary)
    }
}
