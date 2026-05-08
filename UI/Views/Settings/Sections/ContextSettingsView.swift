import SwiftUI
import Shared
import AppKit
import App
import Database

extension SettingsView {
    var contextSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            cliContextCard
            journalContextCard
            privateIntegrationsCard
        }
        .textSelection(.enabled)
        .onChange(of: dailyJournalEnabled) { _ in
            Task { await coordinatorWrapper.coordinator.refreshDailyJournalSchedule() }
        }
    }

    private var cliContextCard: some View {
        ModernSettingsCard(title: "Agent CLI", icon: "terminal") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use `retrace-cli` for explicit, non-interactive context access. Read commands use a read-only database connection and do not start an MCP or HTTP server.")
                    .font(.retraceCaption)
                    .foregroundColor(.retraceSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    cliCommand("retrace-cli context recent --hours 1 --json")
                    cliCommand("retrace-cli context search \"project\" --hours 24 --json")
                    cliCommand("retrace-cli journal today --json")
                    cliCommand("retrace-cli ollama status --model \(dailyJournalOllamaModel) --json")
                }
            }
        }
    }

    private var journalContextCard: some View {
        ModernSettingsCard(title: "Hourly Journal", icon: "book.closed") {
            VStack(alignment: .leading, spacing: 16) {
                ModernToggleRow(
                    title: "Generate local journal summaries",
                    subtitle: "Runs outside capture/OCR, reads completed OCR only, and appends markdown once per hour.",
                    isOn: $dailyJournalEnabled,
                    badge: "Local"
                )

                settingsTextField(
                    title: "Journal folder",
                    text: $dailyJournalFolderPath,
                    placeholder: DailyJournalConfiguration.defaultJournalFolderPath()
                )

                HStack(spacing: 12) {
                    ModernButton(title: "Choose Folder", icon: "folder", style: .secondary) {
                        chooseJournalFolder()
                    }

                    ModernButton(title: isGeneratingJournal ? "Generating..." : "Generate Last Hour", icon: "sparkles", style: .primary) {
                        generateJournalNow()
                    }

                    ModernButton(title: isCheckingOllama ? "Checking..." : "Check Ollama", icon: "bolt.horizontal", style: .secondary) {
                        checkOllamaStatus()
                    }
                }
                .disabled(isGeneratingJournal || isCheckingOllama)

                HStack(spacing: 12) {
                    settingsTextField(
                        title: "Ollama URL",
                        text: $dailyJournalOllamaBaseURL,
                        placeholder: DailyJournalConfiguration.defaultOllamaBaseURLString
                    )

                    settingsTextField(
                        title: "Model",
                        text: $dailyJournalOllamaModel,
                        placeholder: DailyJournalConfiguration.defaultOllamaModel
                    )
                }

                Stepper(
                    "Cadence: \(Int(dailyJournalCadenceSeconds / 60)) minutes",
                    value: $dailyJournalCadenceSeconds,
                    in: 900...21_600,
                    step: 900
                )
                .font(.retraceCaption)
                .foregroundColor(.retraceSecondary)

                if let journalStatusMessage {
                    journalStatusRow(journalStatusMessage)
                }
            }
        }
    }

    private var privateIntegrationsCard: some View {
        ModernSettingsCard(title: "Private Integrations", icon: "lock.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                integrationRow("Obsidian", "Write markdown into a chosen vault/folder first. Local REST/API integration stays opt-in and later.")
                integrationRow("MCP", "Deferred until CLI commands and privacy boundaries settle. Future tools should map to the same safe CLI actions.")
                integrationRow("Scanners", "Package and MCP scanner warnings remain backlog items, not background network services.")
                integrationRow("Models", "Ollama text summarization ships first. MLX, LFM2.5-VL, and llama.cpp stay on the evaluation track.")
            }
        }
    }

    private func cliCommand(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.retraceMono)
                .foregroundColor(.retracePrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyToClipboard(command)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.retraceCaptionMedium)
                    .foregroundColor(.retraceSecondary)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help("Copy command")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Copy Command") {
                copyToClipboard(command)
            }
        }
    }

    private func journalStatusRow(_ message: String) -> some View {
        let path = journalStatusPath(from: message)

        return VStack(alignment: .leading, spacing: 6) {
            Text(path == nil ? "Status" : "Journal output")
                .font(.retraceCaptionMedium)
                .foregroundColor(.retracePrimary)

            HStack(spacing: 8) {
                Text(message)
                    .font(.retraceCaption)
                    .foregroundColor(journalStatusIsError ? .retraceDanger : .retraceSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    copyToClipboard(path.map(shellQuotedPath) ?? message)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.retraceCaptionMedium)
                        .foregroundColor(.retraceSecondary)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help(path == nil ? "Copy status" : "Copy file path")

                if let path {
                    Button {
                        openPath(path)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.retraceCaptionMedium)
                            .foregroundColor(.retraceSecondary)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal journal file")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contextMenu {
                Button(path == nil ? "Copy Status" : "Copy File Path") {
                    copyToClipboard(path.map(shellQuotedPath) ?? message)
                }
                if let path {
                    Button("Reveal in Finder") {
                        openPath(path)
                    }
                }
            }
        }
    }

    private func integrationRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.retraceCaptionMedium)
                .foregroundColor(.retracePrimary)
            Text(detail)
                .font(.retraceCaption2)
                .foregroundColor(.retraceSecondary)
        }
    }

    private func settingsTextField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.retraceCaptionMedium)
                .foregroundColor(.retracePrimary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.retraceCaption)
                .foregroundColor(.retracePrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func journalStatusPath(from message: String) -> String? {
        guard message.hasPrefix("/") else { return nil }
        return message
    }

    private func shellQuotedPath(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func openPath(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func chooseJournalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            dailyJournalFolderPath = url.path
            Task {
                let metadata = Self.inPageURLMetricMetadata(["source": "settings"])
                try? await coordinatorWrapper.coordinator.recordMetricEvent(
                    metricType: .journalFolderChanged,
                    metadata: metadata
                )
            }
        }
    }

    private func checkOllamaStatus() {
        isCheckingOllama = true
        journalStatusMessage = nil
        Task {
            do {
                let status = try await coordinatorWrapper.coordinator.getOllamaJournalStatus()
                await MainActor.run {
                    isCheckingOllama = false
                    journalStatusIsError = !status.isModelInstalled
                    journalStatusMessage = status.isModelInstalled
                        ? "Ollama is reachable and \(status.requestedModel) is installed."
                        : "Ollama is reachable, but \(status.requestedModel) is not installed."
                }
            } catch {
                await MainActor.run {
                    isCheckingOllama = false
                    journalStatusIsError = true
                    journalStatusMessage = "Could not reach Ollama at \(dailyJournalOllamaBaseURL)."
                }
            }
        }
    }

    private func generateJournalNow() {
        isGeneratingJournal = true
        journalStatusMessage = nil
        let end = Date()
        let start = end.addingTimeInterval(-dailyJournalCadenceSeconds)
        Task {
            do {
                let result = try await coordinatorWrapper.coordinator.generateDailyJournalNow(
                    from: start,
                    to: end,
                    dryRun: false
                )
                await MainActor.run {
                    isGeneratingJournal = false
                    journalStatusIsError = result.status == .failed
                    journalStatusMessage = result.filePath ?? result.reason ?? result.status.rawValue
                }
            } catch {
                await MainActor.run {
                    isGeneratingJournal = false
                    journalStatusIsError = true
                    journalStatusMessage = "Journal generation failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
