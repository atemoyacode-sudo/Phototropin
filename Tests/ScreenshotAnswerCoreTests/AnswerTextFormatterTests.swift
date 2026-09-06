import Foundation
import XCTest
@testable import ScreenshotAnswerCore

final class AnswerTextFormatterTests: XCTestCase {
    func testEmphasisMarkersAreNotShownVerbatim() {
        let formatted = AnswerTextFormatter.attributed(
            "The most appropriate word is **\"over\"**."
        )
        XCTAssertEqual(String(formatted.characters), "The most appropriate word is \"over\".")
    }

    func testParagraphBreaksSurviveParsing() {
        let formatted = AnswerTextFormatter.attributed("First line.\n\nSecond line.")
        XCTAssertEqual(String(formatted.characters), "First line.\n\nSecond line.")
    }

    func testLinksFromUntrustedAnswersAreNotRendered() {
        let formatted = AnswerTextFormatter.attributed(
            "Open [the report](https://example.com/report) now."
        )
        XCTAssertEqual(String(formatted.characters), "Open the report now.")
        XCTAssertTrue(formatted.runs.allSatisfy { $0.link == nil })
    }

    func testImagesFromUntrustedAnswersAreNotRendered() {
        let formatted = AnswerTextFormatter.attributed("See ![diagram](https://example.com/a.png).")
        XCTAssertTrue(formatted.runs.allSatisfy { $0.imageURL == nil })
    }

    func testSpacedAsterisksStayLiteral() {
        let formatted = AnswerTextFormatter.attributed("The product is 2 * 3 * 4.")
        XCTAssertEqual(String(formatted.characters), "The product is 2 * 3 * 4.")
    }

    func testBulletMarkersBecomeBulletsInsteadOfLiteralAsterisks() {
        let formatted = AnswerTextFormatter.attributed(
            """
            【本日のおすすめ】

            *  鶏の唐揚げ
                * 価格：680円
            - 出汁巻き玉子
            + 冷奴
            """
        )
        let lines = String(formatted.characters).split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines[2], "• 鶏の唐揚げ")
        XCTAssertEqual(lines[3], "    • 価格：680円")
        XCTAssertEqual(lines[4], "• 出汁巻き玉子")
        XCTAssertEqual(lines[5], "• 冷奴")
        XCTAssertFalse(String(formatted.characters).contains("*"))
    }

    func testTableRowsBecomeReadableLinesWithoutPipes() {
        let formatted = AnswerTextFormatter.attributed(
            """
            | Dish | Price | Note |
            |------|:-----:|------|
            | 冷奴 (Chilled Tofu) | 380円 | Smooth tofu with seasonings. |
            """
        )
        let text = String(formatted.characters)

        XCTAssertEqual(
            text,
            """
            Dish — Price — Note
            冷奴 (Chilled Tofu) — 380円 — Smooth tofu with seasonings.
            """
        )
        XCTAssertFalse(text.contains("|"))
    }

    func testLeadingPipeFromAPrintedRuleIsDropped() {
        let formatted = AnswerTextFormatter.attributed(
            "|Dashimaki Tamago (Rolled Omelet)\n|Hiyayakko (Chilled Tofu)"
        )
        XCTAssertEqual(
            String(formatted.characters),
            "Dashimaki Tamago (Rolled Omelet)\nHiyayakko (Chilled Tofu)"
        )
    }

    func testStrandedClosingPipeIsDropped() {
        let formatted = AnswerTextFormatter.attributed(
            "We finished it lightly, using tofu made from selected soybeans. |"
        )
        XCTAssertEqual(
            String(formatted.characters),
            "We finished it lightly, using tofu made from selected soybeans."
        )
    }

    func testPipesInsideOrdinaryProseAreLeftAlone() {
        let answer = "The shell pipeline a | b is unchanged."
        XCTAssertEqual(String(AnswerTextFormatter.attributed(answer).characters), answer)
    }

    func testHeadingMarkersAreRemoved() {
        let formatted = AnswerTextFormatter.attributed("## 本日のおすすめ\n### 一品料理")
        XCTAssertEqual(String(formatted.characters), "本日のおすすめ\n一品料理")
    }

    func testEmphasisAtTheStartOfALineIsNotMistakenForAList() {
        let formatted = AnswerTextFormatter.attributed("*over* is the answer.")
        XCTAssertEqual(String(formatted.characters), "over is the answer.")
    }

    func testHashWithoutASpaceIsLeftAlone() {
        let answer = "#1 の選択肢が正解です。"
        XCTAssertEqual(String(AnswerTextFormatter.attributed(answer).characters), answer)
    }

    func testPlainAnswersArePreserved() {
        let answer = "get over the shock"
        XCTAssertEqual(String(AnswerTextFormatter.attributed(answer).characters), answer)
    }
}
