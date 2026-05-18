import Foundation
import Database
import Shared

public struct ActivityContextCollectionOptions: Sendable, Equatable {
    public var maxFramesPerWindow: Int
    public var maxCharsPerFrame: Int
    public var maxTotalPromptChars: Int
    public var minimumAgeSeconds: TimeInterval
    public var minimumPromptChars: Int

    public init(
        maxFramesPerWindow: Int,
        maxCharsPerFrame: Int,
        maxTotalPromptChars: Int,
        minimumAgeSeconds: TimeInterval,
        minimumPromptChars: Int
    ) {
        self.maxFramesPerWindow = maxFramesPerWindow
        self.maxCharsPerFrame = maxCharsPerFrame
        self.maxTotalPromptChars = maxTotalPromptChars
        self.minimumAgeSeconds = minimumAgeSeconds
        self.minimumPromptChars = minimumPromptChars
    }

    public static let `default` = ActivityContextCollectionOptions(
        maxFramesPerWindow: 120,
        maxCharsPerFrame: 2_000,
        maxTotalPromptChars: 24_000,
        minimumAgeSeconds: 180,
        minimumPromptChars: 400
    )
}

public struct ActivityContextDigest: Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let samples: [ActivityContextQueries.Sample]
    public let promptText: String
    public let appNames: [String]

    public init(
        startDate: Date,
        endDate: Date,
        samples: [ActivityContextQueries.Sample],
        promptText: String,
        appNames: [String]
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.samples = samples
        self.promptText = promptText
        self.appNames = appNames
    }

    public var hasEnoughText: Bool {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines).count >= ActivityContextCollectionOptions.default.minimumPromptChars
    }
}

public enum JournalGenerationStatus: String, Codable, Sendable, Equatable {
    case generated
    case skipped
    case failed
}

public struct JournalGenerationResult: Codable, Sendable, Equatable {
    public let status: JournalGenerationStatus
    public let reason: String?
    public let filePath: String?
    public let startDate: Date
    public let endDate: Date

    public init(
        status: JournalGenerationStatus,
        reason: String?,
        filePath: String?,
        startDate: Date,
        endDate: Date
    ) {
        self.status = status
        self.reason = reason
        self.filePath = filePath
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct DailyJournalConfiguration: Sendable, Equatable {
    public static let enabledKey = "dailyJournalEnabled"
    public static let folderPathKey = "dailyJournalFolderPath"
    public static let ollamaBaseURLKey = "dailyJournalOllamaBaseURL"
    public static let ollamaModelKey = "dailyJournalOllamaModel"
    public static let cadenceSecondsKey = "dailyJournalCadenceSeconds"
    public static let defaultOllamaBaseURLString = "http://localhost:11434"
    public static let defaultOllamaModel = "gemma4:e4b"
    public static let preferredOllamaModels = [
        "gemma4:e4b",
        "gemma4",
        "gemma4:e2b",
        "qwen3:14b",
        "qwen3:8b",
        "llama3.2:3b"
    ]

    public var isEnabled: Bool
    public var journalFolder: URL
    public var ollamaBaseURL: URL
    public var ollamaModel: String
    public var cadenceSeconds: TimeInterval
    public var collectionOptions: ActivityContextCollectionOptions

    public static func read(
        from defaults: UserDefaults = UserDefaults(suiteName: "io.retrace.app") ?? .standard
    ) -> DailyJournalConfiguration {
        let folderPath = defaults.string(forKey: folderPathKey)
        let baseURLString = defaults.string(forKey: ollamaBaseURLKey) ?? defaultOllamaBaseURLString
        let model = defaults.string(forKey: ollamaModelKey) ?? defaultOllamaModel
        let storedCadence = defaults.double(forKey: cadenceSecondsKey)

        return DailyJournalConfiguration(
            isEnabled: defaults.bool(forKey: enabledKey),
            journalFolder: URL(fileURLWithPath: (folderPath?.isEmpty == false ? folderPath! : defaultJournalFolderPath()), isDirectory: true),
            ollamaBaseURL: validOllamaBaseURL(baseURLString) ?? URL(string: defaultOllamaBaseURLString)!,
            ollamaModel: model,
            cadenceSeconds: storedCadence > 0 ? max(900, storedCadence) : 3_600,
            collectionOptions: .default
        )
    }

    public static func validOllamaBaseURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    public static func defaultJournalFolderPath() -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (documents ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("Retrace Journal", isDirectory: true)
            .path
    }
}

public struct OllamaModelStatus: Codable, Sendable, Equatable {
    public let baseURL: String
    public let requestedModel: String
    public let isReachable: Bool
    public let isModelInstalled: Bool
    public let installedModels: [String]
    public let recommendedModel: String?
    public let pullCommand: String

    public init(
        baseURL: String,
        requestedModel: String,
        isReachable: Bool,
        isModelInstalled: Bool,
        installedModels: [String],
        recommendedModel: String?,
        pullCommand: String
    ) {
        self.baseURL = baseURL
        self.requestedModel = requestedModel
        self.isReachable = isReachable
        self.isModelInstalled = isModelInstalled
        self.installedModels = installedModels
        self.recommendedModel = recommendedModel
        self.pullCommand = pullCommand
    }
}

public enum OllamaClientError: LocalizedError, Sendable, Equatable {
    case modelNotInstalled(model: String, installedModels: [String], recommendedModel: String?)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let model, let installedModels, let recommendedModel):
            if let recommendedModel {
                return "\(model) is not installed. Use \(recommendedModel), or run `ollama pull \(model)`."
            }
            if installedModels.isEmpty {
                return "\(model) is not installed. Run `ollama pull \(model)`."
            }
            return "\(model) is not installed. Installed models: \(installedModels.joined(separator: ", "))."
        }
    }
}

public protocol JournalSummarizationProvider: Sendable {
    func status(model: String) async throws -> OllamaModelStatus
    func summarize(prompt: String, model: String) async throws -> String
}

public struct OllamaClient: JournalSummarizationProvider {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func status(model: String) async throws -> OllamaModelStatus {
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await session.data(from: tagsURL)
        try validateHTTP(response)
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        let names = decoded.models.map(\.name).sorted()
        let recommended = Self.recommendedModel(requestedModel: model, installedModels: names)
        return OllamaModelStatus(
            baseURL: baseURL.absoluteString,
            requestedModel: model,
            isReachable: true,
            isModelInstalled: names.contains(model),
            installedModels: names,
            recommendedModel: recommended,
            pullCommand: "ollama pull \(model)"
        )
    }

    public func summarize(prompt: String, model: String) async throws -> String {
        let modelStatus = try await status(model: model)
        guard modelStatus.isModelInstalled else {
            throw OllamaClientError.modelNotInstalled(
                model: model,
                installedModels: modelStatus.installedModels,
                recommendedModel: modelStatus.recommendedModel
            )
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    Message(role: "system", content: JournalPromptRenderer.systemPrompt),
                    Message(role: "user", content: prompt)
                ],
                stream: false,
                think: false,
                keepAlive: "2m",
                options: RuntimeOptions(
                    temperature: 0.2,
                    topP: 0.9,
                    numPredict: 700,
                    numContext: 32_768
                )
            )
        )

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func recommendedModel(requestedModel: String, installedModels: [String]) -> String? {
        if installedModels.contains(requestedModel) {
            return requestedModel
        }
        for candidate in DailyJournalConfiguration.preferredOllamaModels where installedModels.contains(candidate) {
            return candidate
        }
        return installedModels.first
    }

    private func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private struct TagsResponse: Codable {
        let models: [Model]
    }

    private struct Model: Codable {
        let name: String
    }

    private struct ChatRequest: Codable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let think: Bool
        let keepAlive: String
        let options: RuntimeOptions

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case think
            case keepAlive = "keep_alive"
            case options
        }
    }

    private struct RuntimeOptions: Codable {
        let temperature: Double
        let topP: Double
        let numPredict: Int
        let numContext: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case topP = "top_p"
            case numPredict = "num_predict"
            case numContext = "num_ctx"
        }
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ChatResponse: Codable {
        let message: Message
    }
}

public enum JournalPromptRenderer {
    public static let systemPrompt = """
    You summarize private local screen OCR into a concise personal work journal. Do not invent facts. Do not include secrets, raw file paths, API keys, passwords, or full URLs. Prefer useful project context, decisions, blockers, and next steps.
    """

    public static func render(digest: ActivityContextDigest) -> String {
        """
        Summarize this local activity window as markdown.

        Window: \(timeRange(digest.startDate, digest.endDate))
        Apps: \(digest.appNames.joined(separator: ", "))

        Return exactly:
        - 3-6 summary bullets
        - "Likely focus" with 1-3 short items
        - "Agent context" with useful coding-agent notes
        - "Possible next steps" with 1-4 bullets

        OCR context:
        \(digest.promptText)
        """
    }

    private static func timeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}

public actor LowImpactActivityContextCollector {
    private let database: DatabaseManager

    public init(database: DatabaseManager) {
        self.database = database
    }

    public func collect(
        from startDate: Date,
        to endDate: Date,
        options: ActivityContextCollectionOptions = .default
    ) async throws -> ActivityContextDigest {
        let adjustedEnd = min(endDate, Date().addingTimeInterval(-options.minimumAgeSeconds))
        guard adjustedEnd > startDate else {
            return ActivityContextDigest(startDate: startDate, endDate: adjustedEnd, samples: [], promptText: "", appNames: [])
        }

        let samples = try await database.getActivityContextSamples(
            from: startDate,
            to: adjustedEnd,
            limit: options.maxFramesPerWindow,
            maxTextLength: options.maxCharsPerFrame,
            newestFirst: false
        )

        let appNames = Array(Set(samples.map(\.displayAppName))).sorted()
        var prompt = ""

        for sample in samples {
            try Task.checkCancellation()
            let block = render(sample)
            guard !block.isEmpty else { continue }
            if prompt.count + block.count > options.maxTotalPromptChars {
                break
            }
            prompt += block
            prompt += "\n\n"
        }

        return ActivityContextDigest(
            startDate: startDate,
            endDate: adjustedEnd,
            samples: samples,
            promptText: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            appNames: appNames
        )
    }

    private func render(_ sample: ActivityContextQueries.Sample) -> String {
        let formatter = ISO8601DateFormatter()
        let titleParts = [
            sample.displayAppName,
            sample.windowName
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        let text = [
            sample.chromeText,
            sample.mainText
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")

        guard !text.isEmpty else { return "" }
        return """
        [\(formatter.string(from: sample.timestamp))] \(titleParts.joined(separator: " - "))
        \(text)
        """
    }
}

public actor DailyJournalManager {
    private let database: DatabaseManager
    private let collector: LowImpactActivityContextCollector
    private var task: Task<Void, Never>?
    private var activeGeneration: Task<JournalGenerationResult, Error>?

    public init(database: DatabaseManager) {
        self.database = database
        self.collector = LowImpactActivityContextCollector(database: database)
    }

    public func start() {
        let configuration = DailyJournalConfiguration.read()
        guard configuration.isEnabled else {
            task?.cancel()
            task = nil
            return
        }

        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await self.runLoop(configuration: configuration)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        activeGeneration?.cancel()
        activeGeneration = nil
    }

    public func generateNow(
        from startDate: Date,
        to endDate: Date,
        dryRun: Bool = false
    ) async throws -> JournalGenerationResult {
        let configuration = DailyJournalConfiguration.read()
        return try await generateWindow(
            from: startDate,
            to: endDate,
            configuration: configuration,
            reason: "manual",
            dryRun: dryRun
        )
    }

    public func ollamaStatus() async throws -> OllamaModelStatus {
        let configuration = DailyJournalConfiguration.read()
        let status = try await OllamaClient(baseURL: configuration.ollamaBaseURL)
            .status(model: configuration.ollamaModel)
        try? await recordMetric(.ollamaStatusChecked, metadata: [
            "reachable": status.isReachable,
            "modelInstalled": status.isModelInstalled,
            "model": configuration.ollamaModel
        ])
        return status
    }

    private func runLoop(configuration: DailyJournalConfiguration) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(Int64(configuration.cadenceSeconds)))
                guard !Task.isCancelled else { return }
                let end = Date()
                let start = end.addingTimeInterval(-configuration.cadenceSeconds)
                _ = try await generateWindow(
                    from: start,
                    to: end,
                    configuration: DailyJournalConfiguration.read(),
                    reason: "scheduled",
                    dryRun: false
                )
            } catch is CancellationError {
                return
            } catch {
                Log.error("Daily journal generation failed: \(error)", category: .app)
            }
        }
    }

    private func generateWindow(
        from startDate: Date,
        to endDate: Date,
        configuration: DailyJournalConfiguration,
        reason: String,
        dryRun: Bool
    ) async throws -> JournalGenerationResult {
        if let activeGeneration {
            return try await activeGeneration.value
        }

        let generation = Task<JournalGenerationResult, Error> {
            try await self.performGeneration(
                from: startDate,
                to: endDate,
                configuration: configuration,
                reason: reason,
                dryRun: dryRun
            )
        }
        activeGeneration = generation
        defer { activeGeneration = nil }
        do {
            return try await generation.value
        } catch {
            try? await recordMetric(.journalGenerationFailed, metadata: [
                "reason": reason,
                "error": String(describing: error)
            ])
            throw error
        }
    }

    private func performGeneration(
        from startDate: Date,
        to endDate: Date,
        configuration: DailyJournalConfiguration,
        reason: String,
        dryRun: Bool
    ) async throws -> JournalGenerationResult {
        try? await recordMetric(.journalGenerationRequested, metadata: ["reason": reason, "dryRun": dryRun])

        let digest = try await collector.collect(
            from: startDate,
            to: endDate,
            options: configuration.collectionOptions
        )

        guard digest.promptText.count >= configuration.collectionOptions.minimumPromptChars else {
            let result = JournalGenerationResult(
                status: .skipped,
                reason: "not_enough_completed_ocr",
                filePath: nil,
                startDate: startDate,
                endDate: endDate
            )
            try? await recordMetric(.journalGenerationSkipped, metadata: ["reason": result.reason ?? "unknown"])
            return result
        }

        let writer = DailyJournalWriter(folder: configuration.journalFolder)
        guard !writer.containsWindow(startDate: startDate, endDate: digest.endDate) else {
            let result = JournalGenerationResult(
                status: .skipped,
                reason: "already_summarized",
                filePath: writer.fileURL(for: startDate).path,
                startDate: startDate,
                endDate: digest.endDate
            )
            try? await recordMetric(.journalGenerationSkipped, metadata: ["reason": result.reason ?? "unknown"])
            return result
        }

        let prompt = JournalPromptRenderer.render(digest: digest)
        let summary: String
        if dryRun {
            summary = prompt
        } else {
            do {
                summary = try await OllamaClient(baseURL: configuration.ollamaBaseURL)
                    .summarize(prompt: prompt, model: configuration.ollamaModel)
            } catch let ollamaError as OllamaClientError {
                let result = JournalGenerationResult(
                    status: .failed,
                    reason: ollamaError.localizedDescription,
                    filePath: nil,
                    startDate: startDate,
                    endDate: digest.endDate
                )
                try? await recordMetric(.journalGenerationFailed, metadata: [
                    "reason": reason,
                    "error": result.reason ?? "ollama_error"
                ])
                return result
            } catch let urlError as URLError {
                let result = JournalGenerationResult(
                    status: .failed,
                    reason: "Could not reach Ollama at \(configuration.ollamaBaseURL.absoluteString). Start Ollama, then try again. \(urlError.localizedDescription)",
                    filePath: nil,
                    startDate: startDate,
                    endDate: digest.endDate
                )
                try? await recordMetric(.journalGenerationFailed, metadata: [
                    "reason": reason,
                    "error": "ollama_unreachable"
                ])
                return result
            }
        }

        if dryRun {
            let result = JournalGenerationResult(
                status: .generated,
                reason: "dry_run",
                filePath: nil,
                startDate: startDate,
                endDate: digest.endDate
            )
            try? await recordMetric(.journalGenerationSucceeded, metadata: ["reason": reason, "dryRun": true])
            return result
        }

        let fileURL = try writer.append(
            summary: summary,
            startDate: startDate,
            endDate: digest.endDate,
            sampleCount: digest.samples.count,
            appNames: digest.appNames,
            dryRun: dryRun
        )

        let result = JournalGenerationResult(
            status: .generated,
            reason: dryRun ? "dry_run" : nil,
            filePath: fileURL.path,
            startDate: startDate,
            endDate: digest.endDate
        )
        try? await recordMetric(.journalGenerationSucceeded, metadata: ["reason": reason, "dryRun": dryRun])
        return result
    }

    private func recordMetric(_ metric: DailyMetricsQueries.MetricType, metadata: [String: Any]) async throws {
        let json = DailyJournalManager.metricMetadata(metadata)
        try await database.recordMetricEvent(metricType: metric, metadata: json)
    }

    private static func metricMetadata(_ payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}

public struct DailyJournalWriter: Sendable {
    private let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func fileURL(for date: Date) -> URL {
        folder.appendingPathComponent(Self.dayFormatter.string(from: date) + ".md")
    }

    public func containsWindow(startDate: Date, endDate: Date) -> Bool {
        let marker = Self.marker(startDate: startDate, endDate: endDate)
        guard let content = try? String(contentsOf: fileURL(for: startDate), encoding: .utf8) else {
            return false
        }
        return content.contains(marker)
    }

    public func append(
        summary: String,
        startDate: Date,
        endDate: Date,
        sampleCount: Int,
        appNames: [String],
        dryRun: Bool
    ) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = fileURL(for: startDate)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try frontmatter(for: startDate).write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let section = sectionText(
            summary: summary,
            startDate: startDate,
            endDate: endDate,
            sampleCount: sampleCount,
            appNames: appNames,
            dryRun: dryRun
        )
        let data = Data(section.utf8)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
        return fileURL
    }

    private func frontmatter(for date: Date) -> String {
        """
        ---
        source: retrace
        date: \(Self.dayFormatter.string(from: date))
        privacy: local-only
        ---

        # \(Self.displayDayFormatter.string(from: date))

        """
    }

    private func sectionText(
        summary: String,
        startDate: Date,
        endDate: Date,
        sampleCount: Int,
        appNames: [String],
        dryRun: Bool
    ) -> String {
        """

        \(Self.marker(startDate: startDate, endDate: endDate))
        ## \(Self.timeFormatter.string(from: startDate))-\(Self.timeFormatter.string(from: endDate))

        _Generated by Retrace\(dryRun ? " dry run" : "") from \(sampleCount) OCR samples. Apps: \(appNames.joined(separator: ", "))_

        \(summary)

        """
    }

    private static func marker(startDate: Date, endDate: Date) -> String {
        "<!-- retrace-journal-window: start=\(Int64(startDate.timeIntervalSince1970)) end=\(Int64(endDate.timeIntervalSince1970)) -->"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
