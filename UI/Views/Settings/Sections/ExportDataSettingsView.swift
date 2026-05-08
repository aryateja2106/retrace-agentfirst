import SwiftUI
import Shared
import AppKit
import App
import Database
import Carbon.HIToolbox
import ScreenCaptureKit
import SQLCipher
import ServiceManagement
import Darwin
import Carbon
import UniformTypeIdentifiers

extension SettingsView {
    var exportDataSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            dataSafetyExportCard
        }
    }

    // MARK: - Export & Data Cards (extracted for search)

    @ViewBuilder
    var comingSoonCard: some View {
        dataSafetyExportCard
    }

    @ViewBuilder
    var dataSafetyExportCard: some View {
        ModernSettingsCard(title: "Data Safety Export", icon: "externaldrive.badge.checkmark") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create a local portable export folder with the Retrace database, WAL/SHM sidecars, video chunks or segments, non-secret settings, and a README.")
                    .font(.retraceCalloutMedium)
                    .foregroundColor(.retracePrimary)

                Text("Keychain secrets and decrypted OCR text are not exported outside the copied databases. Use this before moving data out of Trash or between machines.")
                    .font(.retraceCaption)
                    .foregroundColor(.retraceSecondary.opacity(0.7))

                HStack(spacing: 12) {
                    ModernButton(
                        title: isExportingPortableData ? "Exporting..." : "Export Portable Folder",
                        icon: "archivebox",
                        style: .primary
                    ) {
                        choosePortableExportFolder()
                    }
                    .disabled(isExportingPortableData)

                    ModernButton(
                        title: "Copy CLI Audit Command",
                        icon: "terminal",
                        style: .secondary
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "retrace-cli storage audit --include-defaults --manifest ~/Desktop/retrace-recovery-manifest.json",
                            forType: .string
                        )
                        showSettingsToast("CLI audit command copied")
                    }
                }

                if let portableExportPath {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last export")
                            .font(.retraceCaptionMedium)
                            .foregroundColor(.retracePrimary)

                        Text(portableExportPath)
                            .font(.retraceCaption2)
                            .foregroundColor(.retraceSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Text("\(portableExportCopiedItemCount) items copied, \(portableExportWarningCount) warnings")
                            .font(.retraceCaption2)
                            .foregroundColor(portableExportWarningCount == 0 ? .retraceSuccess : .retraceWarning)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.retraceControlFill.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    func choosePortableExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Portable Export Folder"
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        startPortableExport(to: destinationURL)
    }

    func startPortableExport(to destinationURL: URL) {
        isExportingPortableData = true
        showSettingsToast("Starting portable export")
        recordPortableDataExportMetric(action: "requested", destinationPath: destinationURL.path)

        Task {
            do {
                let manifest = try await Task.detached(priority: .utility) {
                    try PortableDataExporter().export(
                        request: PortableExportRequest(
                            destinationPath: destinationURL.path,
                            includeRewind: true,
                            confirmExport: true
                        )
                    )
                }.value

                await MainActor.run {
                    isExportingPortableData = false
                    portableExportPath = manifest.destinationPath
                    portableExportCopiedItemCount = manifest.items.filter { $0.copied }.count
                    portableExportWarningCount = manifest.warnings.count
                    showSettingsToast("Portable export created")
                    recordPortableDataExportMetric(
                        action: "succeeded",
                        destinationPath: manifest.destinationPath,
                        copiedItemCount: portableExportCopiedItemCount,
                        warningCount: portableExportWarningCount
                    )
                }
            } catch {
                await MainActor.run {
                    isExportingPortableData = false
                    showSettingsToast("Portable export failed", isError: true)
                    recordPortableDataExportMetric(
                        action: "failed",
                        destinationPath: destinationURL.path,
                        error: error.localizedDescription
                    )
                }
            }
        }
    }

    func recordPortableDataExportMetric(
        action: String,
        destinationPath: String,
        copiedItemCount: Int? = nil,
        warningCount: Int? = nil,
        error: String? = nil
    ) {
        Task {
            var payload: [String: Any] = [
                "action": action,
                "source": "settings_export_data",
                "destinationPathLength": destinationPath.count
            ]
            if let copiedItemCount {
                payload["copiedItemCount"] = copiedItemCount
            }
            if let warningCount {
                payload["warningCount"] = warningCount
            }
            if let error {
                payload["error"] = error
            }

            try? await coordinatorWrapper.coordinator.recordMetricEvent(
                metricType: .portableDataExport,
                metadata: Self.inPageURLMetricMetadata(payload)
            )
        }
    }

    // MARK: - Privacy Settings
}
