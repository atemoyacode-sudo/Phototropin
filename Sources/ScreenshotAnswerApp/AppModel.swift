import AppKit
import Foundation
import ScreenshotAnswerCore

@MainActor
final class AppModel: ObservableObject {
    @Published var status = "起動中…"
    @Published var recognizedText = ""
    @Published var answer = ""
    @Published private(set) var canDescribeRecognizedContent = false
    @Published private(set) var currentImageURL: URL?
    @Published var availableModels: [String] = []
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: Keys.selectedModel) }
    }
    @Published var speculativeDecodingMode: SpeculativeDecodingMode {
        didSet {
            UserDefaults.standard.set(
                speculativeDecodingMode.rawValue,
                forKey: Keys.speculativeDecodingMode
            )
        }
    }
    @Published var selectedDraftModel: String {
        didSet { UserDefaults.standard.set(selectedDraftModel, forKey: Keys.selectedDraftModel) }
    }
    @Published var monitorsScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(monitorsScreenshots, forKey: Keys.monitorsScreenshots)
            monitorsScreenshots ? startMonitor() : stopMonitor()
        }
    }
    @Published var copiesAnswer: Bool {
        didSet { UserDefaults.standard.set(copiesAnswer, forKey: Keys.copiesAnswer) }
    }
    @Published var showsAnswerPopup: Bool {
        didSet { UserDefaults.standard.set(showsAnswerPopup, forKey: Keys.showsAnswerPopup) }
    }
    @Published var systemAudioLanguage: SystemAudioLanguage {
        didSet { UserDefaults.standard.set(systemAudioLanguage.rawValue, forKey: Keys.systemAudioLanguage) }
    }
    @Published var organizesMultipleSpeakers: Bool {
        didSet {
            UserDefaults.standard.set(
                organizesMultipleSpeakers,
                forKey: Keys.organizesMultipleSpeakers
            )
        }
    }
    @Published var audioQuestion = ""
    @Published private(set) var audioTranscript = ""
    @Published private(set) var isListeningToSystemAudio = false
    @Published private(set) var audioElapsedSeconds = 0
    @Published private(set) var isBusy = false

    let screenshotDirectory = ScreenshotLocation.current()

    private let generator: LMStudioAnswerGenerator
    private let pipeline: ScreenshotAnswerPipeline
    private let overlayController = AnswerOverlayWindowController()
    private let recordingOverlayController = RecordingOverlayWindowController()
    private let systemAudioCapture = SystemAudioCaptureCoordinator()
    private var timer: Timer?
    private var systemAudioTimer: Timer?
    private var seenImages = Set<URL>()
    private var pendingImages: [URL] = []
    private let startedAt = Date()
    private var didStart = false

    init() {
        let defaults = UserDefaults.standard
        Keys.migrateLegacyValues(in: defaults)
        selectedModel = defaults.string(forKey: Keys.selectedModel) ?? ""
        speculativeDecodingMode = SpeculativeDecodingMode(
            rawValue: defaults.string(forKey: Keys.speculativeDecodingMode) ?? ""
        ) ?? .lmStudioDefault
        selectedDraftModel = defaults.string(forKey: Keys.selectedDraftModel) ?? ""
        monitorsScreenshots = defaults.object(forKey: Keys.monitorsScreenshots) as? Bool ?? true
        copiesAnswer = defaults.object(forKey: Keys.copiesAnswer) as? Bool ?? false
        showsAnswerPopup = defaults.object(forKey: Keys.showsAnswerPopup) as? Bool ?? true
        systemAudioLanguage = SystemAudioLanguage(
            rawValue: defaults.string(forKey: Keys.systemAudioLanguage) ?? ""
        ) ?? .english
        organizesMultipleSpeakers = defaults.object(
            forKey: Keys.organizesMultipleSpeakers
        ) as? Bool ?? true
        generator = try! LMStudioAnswerGenerator()
        pipeline = ScreenshotAnswerPipeline(generator: generator)
        Task { @MainActor [weak self] in self?.start() }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        seedSeenImages()
        if monitorsScreenshots { startMonitor() }
        Task { await refreshModels() }
    }

    func refreshModels() async {
        status = "LM Studioモデルを確認中…"
        do {
            let models = try await generator.availableModels()
            availableModels = models
            if selectedModel.isEmpty || !models.contains(selectedModel) {
                selectedModel = models.first ?? ""
            }
            normalizeDraftModelSelection()
            status = models.isEmpty
                ? ScreenshotAnswerError.noLMStudioModel.localizedDescription
                : "スクリーンショットを待っています"
        } catch {
            availableModels = []
            status = error.localizedDescription
        }
    }

    func captureSelection() {
        guard !isBusy else { return }
        let imageURL = nextCaptureURL()
        status = "範囲を選択してください…"
        hideWindowsForCapture()

        Task {
            // MenuBarExtraのパネルが画面から完全に退避してから
            // 範囲選択を始め、パネルの下もドラッグできるようにする。
            try? await Task.sleep(nanoseconds: 180_000_000)
            let captured = await Self.captureSelection(to: imageURL)
            guard captured else {
                status = "撮影をキャンセルしました"
                return
            }
            enqueue(imageURL)
        }
    }

    private func hideWindowsForCapture() {
        overlayController.dismissImmediately()
        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(answer, forType: .string) {
            status = "回答をコピーしました"
        }
    }

    func describeRecognizedContent() {
        guard !isBusy,
              currentImageURL != nil
                || !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedModel.isEmpty else { return }

        let text = recognizedText
        let imageURL = currentImageURL
        let model = selectedModel
        let options = generationOptions
        isBusy = true
        canDescribeRecognizedContent = false
        status = "内容を説明中…"

        Task {
            do {
                let generated: String
                if let imageURL {
                    do {
                        generated = try await generator.describeImage(
                            imageURL: imageURL,
                            recognizedText: text,
                            model: model,
                            options: options
                        )
                    } catch ScreenshotAnswerError.imageModelRequired
                                where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        generated = try await generator.describe(
                            recognizedText: text,
                            model: model,
                            options: options
                        )
                    }
                } else {
                    generated = try await generator.describe(
                        recognizedText: text,
                        model: model,
                        options: options
                    )
                }
                answer = AnswerResponseClassifier.displayText(generated)
                status = "内容を説明しました"
                if copiesAnswer { copyAnswer() }
                if showsAnswerPopup {
                    overlayController.show(
                        answer: answer,
                        recognizedText: text.isEmpty
                            ? "画像（文字は検出されませんでした）"
                            : text,
                        onCopy: { [weak self] in self?.copyAnswer() }
                    )
                }
            } catch {
                status = "説明できませんでした: \(error.localizedDescription)"
                if showsAnswerPopup { overlayController.showFailure(error.localizedDescription) }
            }
            isBusy = false
            processNextIfNeeded()
        }
    }

    func openScreenshotDirectory() {
        NSWorkspace.shared.open(screenshotDirectory)
    }

    func scanNow() {
        scanForNewScreenshots()
    }

    var systemAudioElapsedText: String {
        String(format: "%d:%02d / 1:30", audioElapsedSeconds / 60, audioElapsedSeconds % 60)
    }

    var supportsSystemAudioListening: Bool {
        systemAudioCapture.isSupported
    }

    func startSystemAudioListening() {
        guard !isBusy, !isListeningToSystemAudio else { return }
        isBusy = true
        audioTranscript = ""
        audioElapsedSeconds = 0
        status = "音声認識モデルを準備中…"
        let language = systemAudioLanguage

        Task {
            do {
                try await systemAudioCapture.start(
                    language: language,
                    onTranscript: { [weak self] transcript in
                        Task { @MainActor in
                            guard let self else { return }
                            self.audioTranscript = transcript
                            self.recordingOverlayController.update(transcript: transcript)
                        }
                    }
                )
                isListeningToSystemAudio = true
                isBusy = false
                status = "🔴 システム音声を聞いています"
                startSystemAudioTimer()
                hideWindowsForCapture()
                recordingOverlayController.show(
                    elapsedText: systemAudioElapsedText,
                    language: language.label,
                    question: audioQuestion,
                    transcript: audioTranscript,
                    organizesMultipleSpeakers: organizesMultipleSpeakers,
                    onStop: { [weak self] in self?.stopSystemAudioAndAnswer() }
                )
            } catch {
                isBusy = false
                status = "音声を取得できません: \(error.localizedDescription)"
            }
        }
    }

    func stopSystemAudioAndAnswer() {
        guard isListeningToSystemAudio, !isBusy else { return }
        recordingOverlayController.dismiss()
        isListeningToSystemAudio = false
        isBusy = true
        stopSystemAudioTimer()
        status = "音声を文字起こし中…"

        Task {
            do {
                let transcript = try await systemAudioCapture.stop()
                audioTranscript = transcript
                try await generateAudioAnswer()
            } catch {
                status = "音声を処理できません: \(error.localizedDescription)"
                if showsAnswerPopup { overlayController.showFailure(error.localizedDescription) }
            }
            isBusy = false
            processNextIfNeeded()
        }
    }

    func answerAboutCapturedAudio() {
        guard !isBusy,
              !audioTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedModel.isEmpty else { return }
        isBusy = true
        Task {
            do {
                try await generateAudioAnswer()
            } catch {
                status = "音声について回答できません: \(error.localizedDescription)"
                if showsAnswerPopup { overlayController.showFailure(error.localizedDescription) }
            }
            isBusy = false
            processNextIfNeeded()
        }
    }

    private func generateAudioAnswer() async throws {
        guard !selectedModel.isEmpty else {
            throw ScreenshotAnswerError.noLMStudioModel
        }
        status = "音声の内容を考え中…"
        let screenshotContext = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = try await generator.answerAboutAudio(
            transcript: audioTranscript,
            screenshotText: screenshotContext.isEmpty ? nil : screenshotContext,
            userQuestion: audioQuestion,
            organizeMultipleSpeakers: organizesMultipleSpeakers,
            model: selectedModel,
            options: generationOptions
        )
        answer = AnswerResponseClassifier.displayText(generated)
        canDescribeRecognizedContent = false
        status = "音声の内容へ回答しました"
        if copiesAnswer { copyAnswer() }
        if showsAnswerPopup {
            overlayController.show(
                answer: answer,
                recognizedText: "音声文字起こし: \(audioTranscript)",
                onCopy: { [weak self] in self?.copyAnswer() }
            )
        }
    }

    private func startSystemAudioTimer() {
        stopSystemAudioTimer()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListeningToSystemAudio else { return }
                self.audioElapsedSeconds += 1
                self.recordingOverlayController.update(
                    elapsedText: self.systemAudioElapsedText
                )
                if self.audioElapsedSeconds >= 90 {
                    self.stopSystemAudioAndAnswer()
                }
            }
        }
        systemAudioTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopSystemAudioTimer() {
        systemAudioTimer?.invalidate()
        systemAudioTimer = nil
    }

    private func startMonitor() {
        guard didStart, timer == nil else { return }
        status = "スクリーンショットを待っています"
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanForNewScreenshots() }
        }
        scanForNewScreenshots()
    }

    private func stopMonitor() {
        timer?.invalidate()
        timer = nil
        if didStart { status = "自動監視は停止中です" }
    }

    private func seedSeenImages() {
        seenImages.formUnion(candidateImages())
    }

    private func scanForNewScreenshots() {
        let newImages = candidateImages()
            .filter { !seenImages.contains($0) }
            .filter { modificationDate(of: $0) >= startedAt.addingTimeInterval(-1) }
            .sorted { modificationDate(of: $0) < modificationDate(of: $1) }

        for image in newImages {
            enqueue(image)
        }
    }

    private func candidateImages() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: screenshotDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter(ScreenshotFileClassifier.isLikelyScreenshot)
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func enqueue(_ imageURL: URL) {
        guard !seenImages.contains(imageURL) else { return }
        seenImages.insert(imageURL)
        pendingImages.append(imageURL)
        processNextIfNeeded()
    }

    private func processNextIfNeeded() {
        guard !isBusy, !pendingImages.isEmpty else { return }
        guard !selectedModel.isEmpty else {
            status = ScreenshotAnswerError.noLMStudioModel.localizedDescription
            pendingImages.removeAll()
            return
        }

        let imageURL = pendingImages.removeFirst()
        let model = selectedModel
        let options = generationOptions
        isBusy = true
        status = "文字を認識中…"
        recognizedText = ""
        answer = ""
        canDescribeRecognizedContent = false
        currentImageURL = imageURL

        Task {
            do {
                let result = try await pipeline.process(
                    imageURL: imageURL,
                    model: model,
                    options: options
                )
                recognizedText = result.recognizedText
                status = "回答を生成しました"
                answer = result.answer
                canDescribeRecognizedContent = result.offersContentExplanation
                if copiesAnswer { copyAnswer() }
                if showsAnswerPopup {
                    overlayController.show(
                        answer: result.answer,
                        recognizedText: result.recognizedText.isEmpty
                            ? "画像（文字は検出されませんでした）"
                            : result.recognizedText,
                        onExplain: result.offersContentExplanation
                            ? { [weak self] in self?.describeRecognizedContent() }
                            : nil,
                        onCopy: { [weak self] in self?.copyAnswer() }
                    )
                }
            } catch {
                status = "処理できませんでした: \(error.localizedDescription)"
                if showsAnswerPopup { overlayController.showFailure(error.localizedDescription) }
            }
            isBusy = false
            processNextIfNeeded()
        }
    }

    private func nextCaptureURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let baseName = "Phototropin \(formatter.string(from: Date()))"
        var candidate = screenshotDirectory.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = screenshotDirectory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }
        return candidate
    }

    var availableDraftModels: [String] {
        availableModels.filter { $0 != selectedModel }
    }

    var generationOptions: LMStudioGenerationOptions {
        guard speculativeDecodingMode == .draftModel else {
            return LMStudioGenerationOptions()
        }
        return LMStudioGenerationOptions(draftModel: selectedDraftModel)
    }

    private func normalizeDraftModelSelection() {
        let candidates = availableDraftModels
        if !candidates.contains(selectedDraftModel) {
            selectedDraftModel = candidates.first ?? ""
        }
        if candidates.isEmpty {
            speculativeDecodingMode = .lmStudioDefault
        }
    }

    nonisolated private static func captureSelection(to imageURL: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-i", "-s", "-t", "png", imageURL.path]
                do {
                    try capture.run()
                    capture.waitUntilExit()
                    continuation.resume(returning:
                        capture.terminationStatus == 0
                        && FileManager.default.fileExists(atPath: imageURL.path)
                    )
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

private enum Keys {
    static let selectedModel = "Phototropin.selectedModel"
    static let speculativeDecodingMode = "Phototropin.speculativeDecodingMode"
    static let selectedDraftModel = "Phototropin.selectedDraftModel"
    static let monitorsScreenshots = "Phototropin.monitorsScreenshots"
    static let copiesAnswer = "Phototropin.copiesAnswer"
    static let showsAnswerPopup = "Phototropin.showsAnswerPopup"
    static let systemAudioLanguage = "Phototropin.systemAudioLanguage"
    static let organizesMultipleSpeakers = "Phototropin.organizesMultipleSpeakers"

    private static let migrations = [
        (selectedModel, "PomeVision.selectedModel"),
        (speculativeDecodingMode, "PomeVision.speculativeDecodingMode"),
        (selectedDraftModel, "PomeVision.selectedDraftModel"),
        (monitorsScreenshots, "PomeVision.monitorsScreenshots"),
        (copiesAnswer, "PomeVision.copiesAnswer"),
        (showsAnswerPopup, "PomeVision.showsAnswerPopup"),
        (systemAudioLanguage, "PomeVision.systemAudioLanguage"),
        (organizesMultipleSpeakers, "PomeVision.organizesMultipleSpeakers"),
    ]

    static func migrateLegacyValues(in defaults: UserDefaults) {
        for (newKey, legacyKey) in migrations
        where defaults.object(forKey: newKey) == nil {
            guard let legacyValue = defaults.object(forKey: legacyKey) else { continue }
            defaults.set(legacyValue, forKey: newKey)
        }
    }
}

enum SpeculativeDecodingMode: String, CaseIterable, Identifiable {
    case lmStudioDefault
    case draftModel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lmStudioDefault:
            "LM Studio側の設定"
        case .draftModel:
            "Draft Modelを指定"
        }
    }
}
