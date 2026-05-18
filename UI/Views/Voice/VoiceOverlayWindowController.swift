import App
import AppKit
import Database
import SwiftUI

@MainActor
final class VoiceOverlayWindowController: NSObject, NSWindowDelegate {
    static let shared = VoiceOverlayWindowController()

    private var coordinator: AppCoordinator?
    private var window: NSPanel?
    private var viewModel: VoiceOverlayViewModel?

    private override init() {
        super.init()
    }

    func configure(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func toggle(source: String) {
        if isVisible {
            hide()
        } else {
            show(source: source)
        }
    }

    func show(source: String) {
        let panel = ensureWindow(source: source)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel?.cancel()
    }

    private func ensureWindow(source: String) -> NSPanel {
        if let window {
            viewModel?.startDraftSession(source: source)
            return window
        }

        let viewModel = VoiceOverlayViewModel(
            metricRecorder: { [weak self] event in
                self?.record(event: event)
            }
        )
        viewModel.startDraftSession(source: source)
        self.viewModel = viewModel

        let hostingView = NSHostingView(
            rootView: VoiceOverlayView(
                viewModel: viewModel,
                onClose: { [weak self] in
                    self?.hide()
                },
                onOpenSettings: { [weak self] in
                    self?.openVoiceSettings()
                }
            )
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Voice"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.delegate = self
        window = panel
        return panel
    }

    private func record(event: VoiceOverlayMetricEvent) {
        guard let coordinator else { return }

        switch event {
        case .draftStarted(let source):
            UIMetricsRecorder.recordDictionary(
                coordinator: coordinator,
                type: .voiceOverlayOpened,
                payload: ["source": source]
            )
        case .transcriptCopied(let characterCount, _):
            UIMetricsRecorder.recordDictionary(
                coordinator: coordinator,
                type: .voiceTranscriptCopied,
                payload: ["source": "voice_overlay", "charCount": characterCount]
            )
        case .cancelled(let hadTranscript):
            UIMetricsRecorder.recordDictionary(
                coordinator: coordinator,
                type: .voiceTranscriptCancelled,
                payload: ["source": "voice_overlay", "hadTranscript": hadTranscript]
            )
        case .transcriptUpdated, .customWordsApplied:
            break
        }
    }

    private func openVoiceSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openSettingsVoice, object: nil)
        }
        hide()
    }
}
