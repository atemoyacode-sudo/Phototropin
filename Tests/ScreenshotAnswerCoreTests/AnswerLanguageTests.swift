import Foundation
import XCTest
@testable import ScreenshotAnswerCore

final class AnswerLanguageTests: XCTestCase {
    private let prompt = ScreenshotAnswerPrompt()

    private func system(_ messages: [LMStudioMessage]) throws -> String {
        try XCTUnwrap(messages.first { $0.role == "system" }).content
    }

    private func user(_ messages: [LMStudioMessage]) throws -> String {
        try XCTUnwrap(messages.first { $0.role == "user" }).content
    }

    func testEnglishInterfaceAnswersJapaneseContentInEnglish() throws {
        let messages = prompt.messages(for: "この問題に答えなさい。", language: .english)
        let system = try system(messages)
        XCTAssertTrue(system.contains("Always reply in English"))
        XCTAssertFalse(system.contains("Always reply in Japanese"))
        XCTAssertTrue(system.contains("translate the relevant text into English"))
    }

    func testJapaneseInterfaceAnswersEnglishContentInJapanese() throws {
        let messages = prompt.messages(for: "Answer this question.", language: .japanese)
        let system = try system(messages)
        XCTAssertTrue(system.contains("Always reply in Japanese"))
        XCTAssertFalse(system.contains("Always reply in English"))
    }

    func testUserMessageMatchesTheAnswerLanguage() throws {
        XCTAssertTrue(try user(prompt.messages(for: "x", language: .english))
            .hasPrefix("Answer the question contained"))
        XCTAssertTrue(try user(prompt.messages(for: "x", language: .japanese))
            .hasPrefix("次のOCR結果"))
    }

    func testDescriptionPathsCarryTheTranslationInstruction() throws {
        for language in AnswerLanguage.allCases {
            let expected = language.text(
                "translate the relevant text into Japanese",
                "translate the relevant text into English"
            )
            XCTAssertTrue(
                try system(prompt.descriptionMessages(for: "テスト", language: language))
                    .contains(expected)
            )
            XCTAssertTrue(
                try system(prompt.imageDescriptionMessages(
                    imageBase64: "AAAA",
                    recognizedText: "テスト",
                    language: language
                )).contains(expected)
            )
        }
    }

    func testAudioSpeakerLabelsFollowTheAnswerLanguage() throws {
        let english = try system(prompt.audioMessages(
            transcript: "hello", screenshotText: nil, userQuestion: nil, language: .english
        ))
        XCTAssertTrue(english.contains("Speaker A"))
        XCTAssertFalse(english.contains("話者A"))

        let japanese = try system(prompt.audioMessages(
            transcript: "hello", screenshotText: nil, userQuestion: nil, language: .japanese
        ))
        XCTAssertTrue(japanese.contains("話者A"))
    }

    func testTranslationModeAsksForATranslationInsteadOfASummary() throws {
        let messages = prompt.descriptionMessages(
            for: "鶏の唐揚げ 680円",
            language: .english,
            prefersTranslation: true
        )
        let system = try system(messages)

        XCTAssertTrue(system.contains("Translate the supplied content into English"))
        XCTAssertTrue(system.contains("Do not summarize it"))
        XCTAssertTrue(system.contains("never introduce text that is not present"))
        XCTAssertFalse(system.contains("Explain what the supplied OCR text"))
        XCTAssertTrue(try user(messages).hasPrefix("Translate this content."))
    }

    /// The explanation wording used to survive into translation mode, so the
    /// model returned a page summary, an OCR note and the source text before it
    /// reached the translation.
    func testTranslationModeDropsTheExplanationInstructions() throws {
        for messages in [
            prompt.descriptionMessages(for: "鶏の唐揚げ", language: .english, prefersTranslation: true),
            prompt.imageDescriptionMessages(
                imageBase64: "AAAA",
                recognizedText: "鶏の唐揚げ",
                language: .english,
                prefersTranslation: true
            ),
        ] {
            let system = try system(messages)
            XCTAssertTrue(system.contains("Output the translation and nothing else"))
            XCTAssertTrue(system.contains("Do not restate the source text"))
            XCTAssertFalse(system.contains("summarize the important information"))
            XCTAssertFalse(system.contains("Identify the likely kind of page"))
            XCTAssertFalse(system.contains("Identify the likely scene"))
        }
    }

    func testExplanationRemainsTheDefault() throws {
        let system = try system(prompt.descriptionMessages(for: "x", language: .english))
        XCTAssertTrue(system.contains("Explain what the supplied OCR text"))
        XCTAssertFalse(system.contains("Do not summarize it"))
    }

    func testTranslationModeReachesTheImagePath() throws {
        let system = try system(prompt.imageDescriptionMessages(
            imageBase64: "AAAA",
            recognizedText: nil,
            language: .japanese,
            prefersTranslation: true
        ))
        XCTAssertTrue(system.contains("Translate the supplied content into Japanese"))
        XCTAssertTrue(system.contains("Always reply in Japanese"))
    }

    func testGenerationOptionsCarryTheAnswerLanguage() {
        XCTAssertFalse(LMStudioGenerationOptions().prefersTranslation)
        XCTAssertTrue(
            LMStudioGenerationOptions(prefersTranslation: true).prefersTranslation
        )
        XCTAssertEqual(LMStudioGenerationOptions().answerLanguage, .japanese)
        XCTAssertEqual(
            LMStudioGenerationOptions(answerLanguage: .english).answerLanguage,
            .english
        )
    }
}
