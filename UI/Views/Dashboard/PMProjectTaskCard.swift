import SwiftUI
import AppKit
import Shared
import App

/// Dashboard card: register a project folder, start/stop PM task timers; data lives in `.dot/` inside the project.
struct PMProjectTaskCard: View {
    let projectTaskService: ProjectTaskService

    @State private var projectPath: String = ""
    @State private var newTaskTitle: String = ""
    @State private var tasks: [PMTaskRecord] = []
    @State private var errorText: String?
    @State private var manifest: DotProjectManifest?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects & tasks")
                .font(.retraceHeadline)
                .foregroundColor(.retracePrimary)

            Text("Pick a folder (e.g. a git repo). Time tracking and task notes are stored in \(DotProjectLayout.dotDirectoryName)/ inside that folder.")
                .font(.retraceCaption2)
                .foregroundColor(.retraceSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("Project folder path", text: $projectPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.retraceCaption2)

                Button("Choose…") { pickFolder() }
                    .buttonStyle(.bordered)
            }

            if let manifest {
                Text(manifest.displayName)
                    .font(.retraceCaptionMedium)
                    .foregroundColor(.retraceSecondary)
            }

            HStack(spacing: 8) {
                TextField("Task title", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.retraceCaption2)
                Button("Start") { startTask() }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectURL == nil || newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Stop") { stopTask() }
                    .buttonStyle(.bordered)
                    .disabled(projectURL == nil)
            }

            if let errorText {
                Text(errorText)
                    .font(.retraceCaption2)
                    .foregroundColor(.retraceDanger)
            }

            if !tasks.isEmpty {
                Divider().opacity(0.3)
                ForEach(tasks.reversed().prefix(8)) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.retraceCaptionMedium)
                                .foregroundColor(.retracePrimary)
                            Text(statusLine(task))
                                .font(.retraceCaption2)
                                .foregroundColor(.retraceSecondary)
                        }
                        Spacer()
                        Text(task.status.rawValue)
                            .font(.retraceCaption2)
                            .foregroundColor(.retraceMutedForeground)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.retraceCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.retraceBorder.opacity(0.35), lineWidth: 1)
        )
        .onAppear { refresh() }
        .onChange(of: projectPath) { _ in refresh() }
    }

    private var projectURL: URL? {
        let trimmed = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
        }
    }

    private func refresh() {
        errorText = nil
        manifest = nil
        tasks = []
        guard let url = projectURL else { return }
        do {
            if FileManager.default.fileExists(atPath: ProjectTaskService.dotDirectoryURL(forProjectRoot: url).path) {
                manifest = try projectTaskService.loadManifest(for: url)
                tasks = try projectTaskService.listTasks(for: url)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func startTask() {
        guard let url = projectURL else { return }
        errorText = nil
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            _ = try projectTaskService.registerProject(at: url, displayName: nil)
            _ = try projectTaskService.startTask(for: url, title: title)
            newTaskTitle = ""
            refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func stopTask() {
        guard let url = projectURL else { return }
        errorText = nil
        do {
            _ = try projectTaskService.stopTask(for: url)
            refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func statusLine(_ task: PMTaskRecord) -> String {
        let secs = Int(task.totalTrackedSeconds)
        if task.activeSegment != nil {
            return "Running · \(secs)s tracked"
        }
        return "\(secs)s tracked"
    }
}
