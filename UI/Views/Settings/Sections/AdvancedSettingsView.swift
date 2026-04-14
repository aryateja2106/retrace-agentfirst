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
    var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            cacheCard
            timelineCard
            developerCard
            terminalMemoryCard
            dangerZoneCard
        }
    }

    // MARK: - Advanced Cards (extracted for search)

    @ViewBuilder
    var cacheCard: some View {
        // Placeholder for commented-out Database/Encoding cards
        // TODO: Add Database settings later
//            ModernSettingsCard(title: "Database", icon: "cylinder") {
//                HStack(spacing: 12) {
//                    ModernButton(title: "Vacuum Database", icon: "arrow.triangle.2.circlepath", style: .secondary) {}
//                    ModernButton(title: "Rebuild FTS Index", icon: "magnifyingglass", style: .secondary) {}
//                }
//            }

            // TODO: Add Encoding settings later
//            ModernSettingsCard(title: "Encoding", icon: "cpu") {
//                ModernToggleRow(
//                    title: "Hardware Acceleration",
//                    subtitle: "Use VideoToolbox for faster encoding",
//                    isOn: .constant(true)
//                )
//
//                VStack(alignment: .leading, spacing: 12) {
//                    Text("Encoder Preset")
//                        .font(.retraceCalloutMedium)
//                        .foregroundColor(.retracePrimary)
//
//                    ModernSegmentedPicker(
//                        selection: .constant("balanced"),
//                        options: ["fast", "balanced", "quality"]
//                    ) { option in
//                        Text(option.capitalized)
//                    }
//                }
//            }

        ModernSettingsCard(title: "Cache", icon: "externaldrive") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Clear App Name Cache")
                            .font(.retraceCalloutMedium)
                            .foregroundColor(.retracePrimary)

                        Text("Refresh cached app names if they appear incorrect or outdated")
                            .font(.retraceCaption2)
                            .foregroundColor(.retraceSecondary)
                    }

                    Spacer()

                    ModernButton(title: "Clear Cache", icon: "arrow.clockwise", style: .secondary) {
                        clearAppNameCache()
                    }
                }

            }
        }
    }

    @ViewBuilder
    var timelineCard: some View {
        ModernSettingsCard(title: "Timeline", icon: "play.rectangle") {
                ModernToggleRow(
                    title: "Show video controls",
                    subtitle: "Display play/pause button in the timeline to auto-advance frames",
                    isOn: $showVideoControls
                )
        }
    }

    @ViewBuilder
    var developerCard: some View {
        ModernSettingsCard(title: "Developer", icon: "hammer") {
            // Build info section
            VStack(alignment: .leading, spacing: 6) {
                Text("Build Info")
                    .font(.retraceCaption2Medium)
                    .foregroundColor(.retraceSecondary)

                buildInfoRow(label: "Version", value: BuildInfo.fullVersion)
                buildInfoRow(label: "Build Type", value: AdvancedSettingsViewModel.buildTypeText(isDevBuild: BuildInfo.isDevBuild))
                if AdvancedSettingsViewModel.shouldShowForkRow(isDevBuild: BuildInfo.isDevBuild, forkName: BuildInfo.forkName) {
                    buildInfoRow(label: "Fork", value: BuildInfo.forkName)
                }
                buildInfoRow(label: "Git Commit", value: BuildInfo.gitCommit, fullValue: BuildInfo.gitCommitFull, url: BuildInfo.commitURL)
                buildInfoRow(label: "Branch", value: BuildInfo.gitBranch)
                buildInfoRow(label: "Build Date", value: BuildInfo.buildDate)
                buildInfoRow(label: "Config", value: BuildInfo.buildConfig)
            }

            Divider()
                .padding(.vertical, 8)

            ModernToggleRow(
                title: "Show frame IDs in UI",
                subtitle: "Display frame IDs in the timeline for debugging",
                isOn: $showFrameIDs
            )

            ModernToggleRow(
                title: "Enable frame ID search",
                subtitle: "Allow jumping to frames by ID in the Go to panel",
                isOn: $enableFrameIDSearch
            )

            ModernToggleRow(
                title: "Show OCR debug overlay",
                subtitle: "Display OCR bounding boxes and tile grid in timeline",
                isOn: $showOCRDebugOverlay
            )

            Divider()
                .padding(.vertical, 8)

            ModernButton(title: "Show Database Schema", icon: "doc.text", style: .secondary) {
                loadDatabaseSchema()
                showingDatabaseSchema = true
            }
            .sheet(isPresented: $showingDatabaseSchema) {
                DatabaseSchemaView(schemaText: databaseSchemaText, isPresented: $showingDatabaseSchema)
            }

            if BuildInfo.isDevBuild {
                Divider()
                    .padding(.vertical, 8)

                ModernButton(title: "Reset Master Key", icon: "key.horizontal", style: .danger) {
                    resetMasterKeyForDebug()
                }
            }
        }
    }

    @ViewBuilder
    var terminalMemoryCard: some View {
        ModernSettingsCard(title: "Terminal Memory", icon: "terminal") {
            ModernToggleRow(
                title: "Enable CLI access",
                subtitle: "Allow the local retrace CLI to read terminal-task memory through the app-hosted socket or fallback database access.",
                isOn: $terminalCLIAccessEnabled
            )
            .onChange(of: terminalCLIAccessEnabled) { enabled in
                Task {
                    await coordinatorWrapper.coordinator.refreshTerminalCLIAccess()
                    try? await coordinatorWrapper.coordinator.recordMetricEvent(
                        metricType: .terminalCLIQuery,
                        metadata: terminalMemoryMetricMetadata([
                            "kind": enabled ? "settings_enable_cli" : "settings_disable_cli"
                        ])
                    )
                }
            }

            ModernToggleRow(
                title: "Allow agent frame search",
                subtitle: "Let the CLI search linked frame history in addition to terminal task summaries.",
                isOn: $terminalAllowAgentFrameSearch
            )
            .onChange(of: terminalAllowAgentFrameSearch) { enabled in
                Task {
                    try? await coordinatorWrapper.coordinator.recordMetricEvent(
                        metricType: .terminalCLIQuery,
                        metadata: terminalMemoryMetricMetadata([
                            "kind": enabled ? "settings_enable_frame_search" : "settings_disable_frame_search"
                        ])
                    )
                }
            }

            Divider()
                .padding(.vertical, 8)

            HStack(spacing: 12) {
                ModernButton(title: "Install CLI Symlink", icon: "link.badge.plus", style: .secondary) {
                    installCLISymlink()
                }

                ModernButton(title: "Copy Shell Hook", icon: "doc.on.doc", style: .secondary) {
                    copyShellHookSnippet()
                }
            }
        }
    }

    @ViewBuilder
    func buildInfoRow(label: String, value: String, fullValue: String? = nil, url: URL? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.retraceCaption2)
                .foregroundColor(.retraceSecondary)
                .frame(width: 80, alignment: .trailing)
            if let url {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.8))
                    .textSelection(.enabled)
                    .help(fullValue ?? value)
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            } else {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.retracePrimary)
                    .textSelection(.enabled)
                    .help(fullValue ?? value)
            }
        }
    }

    @ViewBuilder
    var dangerZoneCard: some View {
        ModernSettingsCard(title: "Danger Zone", icon: "exclamationmark.triangle", dangerous: true) {
            HStack(spacing: 12) {
                ModernButton(title: "Reset All Settings", icon: "arrow.counterclockwise", style: .danger) {
                    showingResetConfirmation = true
                }
                ModernButton(title: "Delete All Data", icon: "trash", style: .danger) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will reset all settings to their defaults. Your recordings will not be deleted.")
        }
        .alert("Delete All Data?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete all your recordings and data. This action cannot be undone.")
        }
    }

    // MARK: - Settings Search Card Resolution

    private func copyShellHookSnippet() {
        let shellName = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        ).lastPathComponent
        let snippet = TerminalShellHookBuilder.snippet(for: shellName)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet, forType: .string)

        Task {
            try? await coordinatorWrapper.coordinator.recordMetricEvent(
                metricType: .terminalCLIQuery,
                metadata: terminalMemoryMetricMetadata([
                    "kind": "settings_copy_hook",
                    "shell": shellName
                ])
            )
        }

        showSettingsToast("Copied \(shellName) hook snippet")
    }

    private func installCLISymlink() {
        Task { @MainActor in
            do {
                let sourceURL = try resolveCLIExecutableURL()
                let binDirectory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("bin", isDirectory: true)
                let destinationURL = binDirectory.appendingPathComponent("retrace")
                let fileManager = FileManager.default

                try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

                if fileManager.fileExists(atPath: destinationURL.path) {
                    let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                    let fileType = attributes[.type] as? FileAttributeType
                    guard fileType == .typeSymbolicLink else {
                        throw NSError(
                            domain: "SettingsView",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "\(destinationURL.path) already exists and is not a symlink."]
                        )
                    }
                    try fileManager.removeItem(at: destinationURL)
                }

                try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)

                try? await coordinatorWrapper.coordinator.recordMetricEvent(
                    metricType: .terminalCLIQuery,
                    metadata: terminalMemoryMetricMetadata([
                        "kind": "settings_install_symlink",
                        "path": destinationURL.path
                    ])
                )

                showSettingsToast("Installed ~/bin/retrace")
            } catch {
                showSettingsToast("CLI install failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    private func resolveCLIExecutableURL() throws -> URL {
        let executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let executableDirectory = executableURL.deletingLastPathComponent()
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        let candidates = [
            executableDirectory.appendingPathComponent("RetraceCLI"),
            currentDirectory.appendingPathComponent(".build/debug/RetraceCLI"),
            currentDirectory.appendingPathComponent(".build/release/RetraceCLI")
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match
        }

        throw NSError(
            domain: "SettingsView",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Couldn't find RetraceCLI. Build it first with `swift build`."]
        )
    }

    private func terminalMemoryMetricMetadata(_ payload: [String: Any]) -> String? {
        DashboardViewModel.metricMetadataJSON(payload)
    }
}
