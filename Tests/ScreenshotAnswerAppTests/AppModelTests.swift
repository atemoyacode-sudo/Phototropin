import AppKit
import Foundation
import XCTest
import ScreenshotAnswerCore
@testable import ScreenshotAnswerApp

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var session: URLSession!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "PhototropinTests.\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: "Phototropin.monitorsScreenshots")
        defaults.set(false, forKey: "Phototropin.showsAnswerPopup")
        defaults.set(false, forKey: "Phototropin.copiesAnswer")
        defaults.set("test-model", forKey: "Phototropin.selectedModel")
        mockLMStudio.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppMockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: root)
    }

    private func makeModel(
        audio: FakeAudioCapture? = nil,
        capture: (@Sendable (URL) async -> Bool)? = nil,
        recognizer: any ScreenshotTextRecognizing = QuestionRecognizer(),
        directoryProvider: (() -> URL)? = nil
    ) throws -> AppModel {
        AppModel(
            defaults: defaults,
            generator: try LMStudioAnswerGenerator(session: session),
            recognizer: recognizer,
            screenshotDirectory: directoryProvider == nil ? root : nil,
            screenshotDirectoryProvider: directoryProvider ?? { self.root },
            temporaryCaptureStore: TemporaryCaptureStore(baseDirectory: root),
            systemAudioCapture: audio ?? FakeAudioCapture(),
            recordingOverlayController: FakeRecordingOverlay(),
            captureImage: capture,
            startsAutomatically: false
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for app state")
    }

    func testNetworkErrorsRespectInterfaceLanguage() {
        let timeout = ScreenshotAnswerError.lmStudioNetworkError(URLError.timedOut.rawValue)
        XCTAssertTrue(InterfaceLanguage.japanese.errorDescription(for: timeout).contains("タイムアウト"))
        XCTAssertTrue(InterfaceLanguage.english.errorDescription(for: timeout).contains("timed out"))
        for code in [URLError.timedOut, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
                     .notConnectedToInternet, .networkConnectionLost, .cancelled, .badServerResponse] {
            let error = ScreenshotAnswerError.lmStudioNetworkError(code.rawValue)
            let english = InterfaceLanguage.english.errorDescription(for: error)
            XCTAssertTrue(english.unicodeScalars.allSatisfy { $0.isASCII }, english)
        }
    }

    func testMonitoringFollowsChangedScreenshotDirectory() async throws {
        let oldDirectory = root.appendingPathComponent("old")
        let newDirectory = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        var currentDirectory = oldDirectory
        let model = try makeModel(directoryProvider: { currentDirectory })
        currentDirectory = newDirectory
        try Data([1]).write(to: newDirectory.appendingPathComponent("Screenshot moved.png"))
        model.scanNow()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.screenshotDirectory, newDirectory)
        XCTAssertEqual(model.answer, "4")
    }

    func testAreaCaptureUsesChangedScreenshotDirectoryWithoutScan() async throws {
        let oldDirectory = root.appendingPathComponent("old")
        let newDirectory = root.appendingPathComponent("new")
        var currentDirectory = oldDirectory
        let capture = CaptureGate()
        let model = try makeModel(capture: { await capture.capture($0) }, directoryProvider: { currentDirectory })
        currentDirectory = newDirectory
        model.captureSelection()
        try await Task.sleep(nanoseconds: 250_000_000)
        let urls = await capture.urls
        XCTAssertEqual(urls.first?.deletingLastPathComponent().path, newDirectory.path)
        await capture.finish()
        try await waitUntil { !model.isBusy }
    }

    func testRecordingDefersScreenshotsAndCanStopImmediately() async throws {
        let audio = FakeAudioCapture()
        let model = try makeModel(audio: audio)
        model.startSystemAudioListening()
        try await waitUntil { model.isListeningToSystemAudio }
        let screenshot = root.appendingPathComponent("Screenshot during recording.png")
        try Data([1]).write(to: screenshot)
        model.scanNow()
        XCTAssertFalse(model.isBusy, "Screenshot work must not block recording stop")
        model.stopSystemAudioAndAnswer()
        XCTAssertFalse(model.isListeningToSystemAudio, "The stop action must take effect immediately")
        // Drain both operations even when the original stop guard rejects the first attempt.
        try await waitUntil { !model.isBusy }
        if model.isListeningToSystemAudio { model.stopSystemAudioAndAnswer() }
        try await waitUntil { audio.stopCount == 1 && !model.isBusy }
        XCTAssertEqual(model.recognizedText, "What is 2 + 2?")
        XCTAssertEqual(model.answer, "4")
    }

    func testAreaCaptureReservesBusyStateUntilCanceled() async throws {
        let capture = CaptureGate()
        let model = try makeModel(capture: { await capture.capture($0) })
        model.captureSelection()
        model.captureSelection()
        XCTAssertTrue(model.isBusy, "Area selection must reserve the operation synchronously")
        try await Task.sleep(nanoseconds: 250_000_000)
        let urls = await capture.urls
        XCTAssertEqual(urls.count, 1, "Repeated capture must not start another selector")
        let screenshot = root.appendingPathComponent("Screenshot while selecting.png")
        try Data([1]).write(to: screenshot)
        model.scanNow()
        XCTAssertTrue(model.recognizedText.isEmpty)
        await capture.finish()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.answer, "4", "Canceling selection must resume queued work")
    }

    /// The automatic vision hand-off used to build fresh default options, which
    /// silently answered an English interface in Japanese.
    func testAutomaticImageExplanationKeepsTheInterfaceLanguage() async throws {
        defaults.set("english", forKey: "Phototropin.interfaceLanguage")
        mockLMStudio.script(
            models: #"{"models":[{"type":"llm","key":"test-model"},{"type":"llm","key":"vision-model","capabilities":{"vision":true}}]}"#,
            chatContents: ["[NO_QUESTION]", "Fried chicken, 680 yen"]
        )

        let model = try makeModel(recognizer: MenuRecognizer())
        let screenshot = root.appendingPathComponent("Screenshot menu.png")
        try makePNGData().write(to: screenshot)
        model.scanNow()
        try await waitUntil { model.answer == "Fried chicken, 680 yen" }

        let bodies = mockLMStudio.chatBodies
        XCTAssertEqual(bodies.count, 2, "The vision hand-off should be the second request")
        let visionRequest = try XCTUnwrap(bodies.last)
        XCTAssertTrue(visionRequest.contains("vision-model"))
        XCTAssertTrue(visionRequest.contains("Always reply in English"))
        XCTAssertTrue(visionRequest.contains("translate the relevant text into English"))
        XCTAssertFalse(visionRequest.contains("Always reply in Japanese"))
    }

    /// Translation must not depend on the model emitting `[NO_QUESTION]`, and
    /// must not spend a round trip asking whether a question is present.
    func testTranslationModeTranslatesInOneRequestWithoutTheImage() async throws {
        defaults.set("english", forKey: "Phototropin.interfaceLanguage")
        defaults.set(true, forKey: "Phototropin.prefersTranslation")
        mockLMStudio.script(
            models: #"{"models":[{"type":"llm","key":"test-model"},{"type":"llm","key":"vision-model","capabilities":{"vision":true}}]}"#,
            // A model that ignores the marker and summarizes instead must not
            // be able to derail translation.
            chatContents: ["Fried chicken, 680 yen", "There is no specific question asked."]
        )

        let model = try makeModel(recognizer: MenuRecognizer())
        try makePNGData().write(to: root.appendingPathComponent("Screenshot menu.png"))
        model.scanNow()
        try await waitUntil { model.answer == "Fried chicken, 680 yen" }

        let bodies = mockLMStudio.chatBodies
        XCTAssertEqual(bodies.count, 1, "Translation should take exactly one request")
        let request = try XCTUnwrap(bodies.first)
        XCTAssertTrue(request.contains("test-model"), "The already selected model should answer")
        XCTAssertFalse(request.contains("vision-model"), "No vision hand-off should happen")
        XCTAssertFalse(request.contains("image_url"), "The image should not be sent")
        XCTAssertFalse(request.contains("NO_QUESTION"), "The question pass should be skipped")
        XCTAssertTrue(request.contains("Translate the supplied content into English"))
        XCTAssertTrue(request.contains("Output the translation and nothing else"))
    }

    func testScreenshotWaitsForModelRefreshInsteadOfBeingLost() async throws {
        let model = try makeModel()
        model.selectedModel = ""
        let screenshot = root.appendingPathComponent("Screenshot before model.png")
        try Data([1]).write(to: screenshot)
        model.scanNow()
        XCTAssertFalse(model.isBusy)
        await model.refreshModels()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.recognizedText, "What is 2 + 2?")
        XCTAssertEqual(model.answer, "4", "Model refresh must resume the saved screenshot")
    }

    func testTemporaryCaptureIsDeletedWhenNoModelIsAvailable() async throws {
        let model = try makeModel(capture: { url in
            try? Data([1]).write(to: url)
            return true
        })
        model.selectedModel = ""
        model.captureStorageMode = .temporary
        model.captureSelection()
        try await waitUntil { !model.isBusy }
        let temporary = TemporaryCaptureStore(baseDirectory: root).directoryURL
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [])
        await model.refreshModels()
        XCTAssertTrue(model.answer.isEmpty, "Discarded temporary captures must not be resumed")
    }

    func testSuccessfulTemporaryCaptureIsAnsweredThenDeleted() async throws {
        let model = try makeModel(capture: { url in
            try? Data([1]).write(to: url)
            return true
        })
        model.captureStorageMode = .temporary
        model.captureSelection()
        try await waitUntil { !model.isBusy }
        XCTAssertEqual(model.answer, "4")
        XCTAssertNil(model.currentImageURL)
        let temporary = TemporaryCaptureStore(baseDirectory: root).directoryURL
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporary.path), [])
    }

    func testRealOCRFlowsFromWatchedImageToMockLMStudio() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(CGColor(gray: 1, alpha: 1))
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 800, height: 200))
        ("What is 2 + 2?" as NSString).draw(at: NSPoint(x: 40, y: 80), withAttributes: [
            .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black,
        ])
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let screenshot = root.appendingPathComponent("Screenshot OCR integration.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: screenshot)
        let model = try makeModel(recognizer: VisionTextRecognizer(recognitionLanguages: ["en-US"]))
        model.scanNow()
        try await waitUntil { !model.isBusy }
        XCTAssertTrue(model.recognizedText.contains("What is 2"), model.recognizedText)
        XCTAssertEqual(model.answer, "4")
    }

}

private struct MenuRecognizer: ScreenshotTextRecognizing {
    func recognizeText(in imageURL: URL) async throws -> String {
        "本日のおすすめ\n鶏の唐揚げ 680円"
    }
}

private func makePNGData() throws -> Data {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let pixels = try XCTUnwrap(bitmap.bitmapData)
    pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
}

private struct QuestionRecognizer: ScreenshotTextRecognizing {
    func recognizeText(in imageURL: URL) async throws -> String { "What is 2 + 2?" }
}

@MainActor
private final class FakeAudioCapture: SystemAudioCapturing {
    var isSupported: Bool { true }
    var stopCount = 0
    func start(language: SystemAudioLanguage, onTranscript: @escaping @Sendable (String) -> Void) async throws {}
    func stop() async throws -> String {
        stopCount += 1
        return "What is 2 + 2?"
    }
}

@MainActor
private final class FakeRecordingOverlay: RecordingOverlayPresenting {
    func show(
        elapsedText: String, language: String, interfaceLanguage: InterfaceLanguage,
        question: String, transcript: String, organizesMultipleSpeakers: Bool,
        onStop: @escaping () -> Void
    ) {}
    func update(elapsedText: String?, transcript: String?) {}
    func dismiss() {}
}

private actor CaptureGate {
    var urls: [URL] = []
    private var continuations: [CheckedContinuation<Bool, Never>] = []
    func capture(_ url: URL) async -> Bool {
        urls.append(url)
        return await withCheckedContinuation { continuations.append($0) }
    }
    func finish() {
        for continuation in continuations { continuation.resume(returning: false) }
        continuations.removeAll()
    }
}

/// Scripted LM Studio replies plus the request bodies that produced them, so a
/// test can assert what the app actually sent.
private final class MockLMStudio: @unchecked Sendable {
    private let lock = NSLock()
    private var queuedChatContents: [String] = []
    private var sentChatBodies: [String] = []
    private var modelsJSON = #"{"models":[{"type":"llm","key":"test-model"}]}"#

    func reset() {
        lock.withLock {
            queuedChatContents = []
            sentChatBodies = []
            modelsJSON = #"{"models":[{"type":"llm","key":"test-model"}]}"#
        }
    }

    func script(models: String? = nil, chatContents: [String] = []) {
        lock.withLock {
            if let models { modelsJSON = models }
            queuedChatContents = chatContents
        }
    }

    var chatBodies: [String] { lock.withLock { sentChatBodies } }

    fileprivate func models() -> String { lock.withLock { modelsJSON } }

    fileprivate func nextChatContent(for body: String) -> String {
        lock.withLock {
            sentChatBodies.append(body)
            return queuedChatContents.isEmpty ? "4" : queuedChatContents.removeFirst()
        }
    }
}

private let mockLMStudio = MockLMStudio()

private final class AppMockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let json: String
        if request.url?.path == "/api/v1/models" {
            json = mockLMStudio.models()
        } else {
            let content = mockLMStudio.nextChatContent(for: Self.body(of: request))
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            json = #"{"choices":[{"message":{"content":"\#(escaped)"}}]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    /// URLSession replaces `httpBody` with a stream before a protocol sees it.
    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
